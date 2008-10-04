require 'rubygems'
require File.dirname(__FILE__) + '/../lib/ebb'
require 'test/unit'
require 'net/http'
require 'socket'
require 'rubygems'
require 'json'


Ebb.log = File.open('/dev/null','w')

TEST_PORT = 4044


class HelperApp
  def call(env)
    commands = env['PATH_INFO'].split('/')
    
    if commands.include?('bytes')
      n = commands.last.to_i
      raise "bytes called with n <= 0" if n <= 0
      body = "C"*n
      status = 200
      
    elsif commands.include?('test_post_length')
      input_body = env['rack.input'].read
      
      content_length_header = env['HTTP_CONTENT_LENGTH'].to_i
      
      if content_length_header == input_body.length
        body = "Content-Length matches input length"
        status = 200
      else
        body = "Content-Length header is #{content_length_header} but body length is #{input_body.length}"
        status = 500
      end
      
    else
      status = 404
      body = "Undefined url"
    end
    
    env['rack.input'] = env['rack.input'].read
    env.delete('rack.errors')
    env['output'] = body
    env['status'] = status
    
    [status, {'Content-Type' => 'text/json'}, env.to_json]
  end
end

class Test::Unit::TestCase
  def get(path)
    response = Net::HTTP.get_response(URI.parse("http://0.0.0.0:#{TEST_PORT}#{path}"))
  end
  
  def post(path, data)
    response = Net::HTTP.post_form(URI.parse("http://0.0.0.0:#{TEST_PORT}#{path}"), data)
  end
end

class ServerTest < Test::Unit::TestCase
  def get(path)
    response = Net::HTTP.get_response(URI.parse("http://0.0.0.0:#{TEST_PORT}#{path}"))
    env = JSON.parse(response.body)
  end

  def post(path, data)
    response = Net::HTTP.post_form(URI.parse("http://0.0.0.0:#{TEST_PORT}#{path}"), data)
    env = JSON.parse(response.body)
  end
  
  def setup
    Thread.new { Ebb.start_server(HelperApp.new, :port => TEST_PORT) }
    sleep 0.1 until Ebb.running?
  end
  
  def teardown
    Ebb.stop_server
    sleep 0.1 while Ebb.running?
  end
  
  def default_test
    assert true
  end
end

class ServerTestFD < ServerTest
  def setup
    @tcp_server = TCPServer.new('0.0.0.0', TEST_PORT);
    Thread.new { Ebb.start_server(HelperApp.new, :fileno => @tcp_server.fileno) }
    sleep 0.1 until Ebb.running?
  end

  def teardown
    super
    @tcp_server = nil
  end
end

class ServerTestSocket < ServerTest
  def get(path)
    socket = UNIXSocket.open(@socketfile)
    socket.write("GET #{path} HTTP/1.0\r\n\r\n")
    response = ""
    while chunk = socket.read(100)
      response << chunk
    end
    body = response.split("\r\n\r\n")[1]
    env = JSON.parse(body)
  ensure
    socket.close if socket
  end
  
  def post(path, data)
    socket = UNIXSocket.open(@socketfile)
    socket.write("POST #{path} HTTP/1.0\r\nContent-Length: #{data.length}\r\n\r\n#{data}")
    response = ""
    while chunk = socket.read(100)
      response << chunk
    end
    body = response.split("\r\n\r\n")[1]
    env = JSON.parse(body)
  ensure
    socket.close if socket
  end
  
  def setup
    @socketfile = '/tmp/ebb_unittest.sock'
    Thread.new { Ebb.start_server(HelperApp.new, :unix_socket => @socketfile) }
    sleep 0.1 until Ebb.running?
  end

  def teardown
    super
  end
end

