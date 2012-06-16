#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'args_parser'
require 'eventmachine'
require 'evma_httpserver'
require 'json'
require 'yaml'
require 'skype'

parser = ArgsParser.parse ARGV do
  arg :help, 'show help', :alias => :h
  arg :port, 'http port', :default => 8787
  arg :list, 'show chat list'
  arg :config, 'config file path', :alias => :c, :default => "#{File.dirname __FILE__}/config.yaml"
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
  STDERR.puts 'config.yaml load error!!'
  exit 1
end

Skype.init @@conf['app_name']
Skype.attach_wait
@@app = Skype::Application.new(@@conf['app_name'])
def skype(command)
  @@app.invoke(command)
end

class SkypeHttpServer  < EM::Connection
  include EM::HttpServer

  def process_http_request
    res = EM::DelegatedHttpResponse.new(self)
    puts "* http #{@http_request_method} #{@http_path_info} #{@http_query_string} #{@http_post_content}"
    begin
      if @http_path_info =~ /^\/.+/
        puts @chat_name = @http_path_info.scan(/^\/(.+)/).first.first
        puts @chat_id = @@conf['chats'][@chat_name]
      end
      if @http_request_method == 'POST'
        puts cmd = "chatmessage #{@chat_id} #{@http_post_content}"
        res.content = skype cmd
        res.status = 200
        res.send_response
      elsif @http_request_method == 'GET'
        res.status = 200
        res.content = 'skype-chat-gateway.'
        res.send_response
      end
    rescue => e
      res.content = e.to_s
      res.status = 500
      res.send_response
    end
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
