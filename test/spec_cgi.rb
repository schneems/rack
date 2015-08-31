require 'minitest/autorun'
begin
require File.expand_path('../testrequest', __FILE__)
require 'rack/handler/cgi'

describe Rack::Handler::CGI do
  include TestRequest::Helpers

  before do
  @host = '127.0.0.1'
  @port = 9203
  end

  if `which lighttpd` && !$?.success?
    raise "lighttpd not found"
  end

  # Keep this first.
  PID = fork {
    ENV['RACK_ENV'] = 'deployment'
    ENV['RUBYLIB'] = [
      File.expand_path('../../lib', __FILE__),
      ENV['RUBYLIB'],
    ].compact.join(':')

    Dir.chdir(File.expand_path("../cgi", __FILE__)) do
      exec "lighttpd -D -f lighttpd.conf"
    end
  }

  Minitest.after_run do
    Process.kill 15, PID
    Process.wait(PID)
  end

  it "respond" do
    sleep 1
    GET("/test")
    response.wont_be :nil?
  end

  it "be a lighttpd" do
    GET("/test")
    status.must_equal 200
    response["SERVER_SOFTWARE"].must_match(/lighttpd/)
    response["HTTP_VERSION"].must_equal "HTTP/1.1"
    response["SERVER_PROTOCOL"].must_equal "HTTP/1.1"
    response["server_port"].must_equal @port.to_s
    response["server_name"].must_equal @host
  end

  it "have rack headers" do
    GET("/test")
    response["rack.version"].must_equal [1,3]
    assert_equal false, response["rack.multithread"]
    assert_equal true, response["rack.multiprocess"]
    assert_equal true, response["rack.run_once"]
  end

  it "have CGI headers on GET" do
    GET("/test")
    response["request_method"].must_equal "GET"
    response["script_name"].must_equal "/test"
    response["REQUEST_PATH"].must_equal "/"
    response["path_info"].must_be_nil
    response["query_string"].must_equal ""
    response["test.postdata"].must_equal ""

    GET("/test/foo?quux=1")
    response["request_method"].must_equal "GET"
    response["script_name"].must_equal "/test"
    response["REQUEST_PATH"].must_equal "/"
    response["path_info"].must_equal "/foo"
    response["query_string"].must_equal "quux=1"
  end

  it "have CGI headers on POST" do
    POST("/test", {"rack-form-data" => "23"}, {'X-test-header' => '42'})
    status.must_equal 200
    response["request_method"].must_equal "POST"
    response["script_name"].must_equal "/test"
    response["REQUEST_PATH"].must_equal "/"
    response["query_string"].must_equal ""
    response["HTTP_X_TEST_HEADER"].must_equal "42"
    response["test.postdata"].must_equal "rack-form-data=23"
  end

  it "support HTTP auth" do
    GET("/test", {:user => "ruth", :passwd => "secret"})
    response["HTTP_AUTHORIZATION"].must_equal "Basic cnV0aDpzZWNyZXQ="
  end

  it "set status" do
    GET("/test?secret")
    status.must_equal 403
    response["rack.url_scheme"].must_equal "http"
  end
end

rescue RuntimeError
  $stderr.puts "Skipping Rack::Handler::CGI tests (lighttpd is required). Install lighttpd and try again."
rescue NotImplementedError
  $stderr.puts "Your Ruby implemenation or platform does not support fork. Skipping Rack::Handler::CGI tests."
end
