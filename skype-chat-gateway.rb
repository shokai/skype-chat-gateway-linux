#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'args_parser'
require 'eventmachine'
require 'evma_httpserver'
require 'json'
require 'skype'

parser = ArgsParser.parse ARGV do
  arg :help, 'show help', :alias => :h
  arg :port, 'http port', :default => 8787
  arg :list, 'show chat list'
  arg :config, 'config file path', :alias => :c, :default => "#{File.dirname __FILE__}/config.yml"
end

if parser.has_option? :help
  puts parser.help
  puts "#{$0} -list"
  puts "#{$0} -run"
  exit
end

begin
  @@conf = YAML::load open(parser[:config])
  p @@conf
rescue => e
  STDERR.puts e
  STDERR.puts 'config.yml load error!!'
  exit 1
end

def skype(command)
  (@@app ||= (
              Skype.init @@conf['app_name']
              Skype.attach_wait
              Skype::Application.new(@@conf['app_name'])
              )).invoke command
end

class SkypeHttpServer  < EM::Connection
  include EM::HttpServer

  def process_http_request
    res = EM::DelegatedHttpResponse.new(self)
    puts "* http #{@http_request_method} #{@http_path_info} #{@http_query_string} #{@http_post_content}"
    begin
      case @http_path_info
      when /^\/chat\/.+/
        to = @@conf['chats'][ @http_path_info.scan(/^\/chat\/(.+)/)[0][0] ]
        case @http_request_method
        when 'POST'
          res.content = skype "CHATMESSAGE #{to} #{@http_post_content}"
          res.status = 200
        end
      when /^\/message\/.+/
        to = @http_path_info.scan(/^\/message\/(.+)/)[0][0]
        case @http_request_method
        when 'POST'
          res.content = skype "MESSAGE #{to} #{@http_post_content}"
          res.status
        end
      when '/'
        res.content = 'skype-chat-gateway - https://github.com/shokai/skype-chat-gateway-linux'
        res.status = 200
      else
        res.content = 'not found'
        res.status = 404
      end
    rescue => e
      STDERR.puts e
      res.content = e.to_s
      res.status = 500
    end
    res.send_response
  end
end


if parser.has_option? :list
  skype('SEARCH RECENTCHATS').split(/,* /).each do |c|
    puts c
  end
  exit
end


EM::run do
  EM::start_server('0.0.0.0', parser[:port].to_i, SkypeHttpServer)
  puts "start HTTP server - port #{parser[:port].to_i}"
end
