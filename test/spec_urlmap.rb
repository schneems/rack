require 'minitest/autorun'
require 'rack/urlmap'
require 'rack/mock'

describe Rack::URLMap do
  it "dispatches paths correctly" do
    app = lambda { |env|
      [200, {
        'x-scriptname' => env['script_name'],
        'x-pathinfo' => env['path_info'],
        'content-type' => 'text/plain'
      }, [""]]
    }
    map = Rack::Lint.new(Rack::URLMap.new({
      'http://foo.org/bar' => app,
      '/foo' => app,
      '/foo/bar' => app
    }))

    res = Rack::MockRequest.new(map).get("/")
    res.must_be :not_found?

    res = Rack::MockRequest.new(map).get("/qux")
    res.must_be :not_found?

    res = Rack::MockRequest.new(map).get("/foo")
    res.must_be :ok?
    res["x-scriptname"].must_equal "/foo"
    res["x-pathinfo"].must_equal ""

    res = Rack::MockRequest.new(map).get("/foo/")
    res.must_be :ok?
    res["x-scriptname"].must_equal "/foo"
    res["x-pathinfo"].must_equal "/"

    res = Rack::MockRequest.new(map).get("/foo/bar")
    res.must_be :ok?
    res["x-scriptname"].must_equal "/foo/bar"
    res["x-pathinfo"].must_equal ""

    res = Rack::MockRequest.new(map).get("/foo/bar/")
    res.must_be :ok?
    res["x-scriptname"].must_equal "/foo/bar"
    res["x-pathinfo"].must_equal "/"

    res = Rack::MockRequest.new(map).get("/foo///bar//quux")
    res.status.must_equal 200
    res.must_be :ok?
    res["x-scriptname"].must_equal "/foo/bar"
    res["x-pathinfo"].must_equal "//quux"

    res = Rack::MockRequest.new(map).get("/foo/quux", "script_name" => "/bleh")
    res.must_be :ok?
    res["x-scriptname"].must_equal "/bleh/foo"
    res["x-pathinfo"].must_equal "/quux"

    res = Rack::MockRequest.new(map).get("/bar", 'http_host' => 'foo.org')
    res.must_be :ok?
    res["x-scriptname"].must_equal "/bar"
    res["x-pathinfo"].must_be :empty?

    res = Rack::MockRequest.new(map).get("/bar/", 'http_host' => 'foo.org')
    res.must_be :ok?
    res["x-scriptname"].must_equal "/bar"
    res["x-pathinfo"].must_equal '/'
  end


  it "dispatches hosts correctly" do
    map = Rack::Lint.new(Rack::URLMap.new("http://foo.org/" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "foo.org",
                                "x-host" => env["http_host"] || env["server_name"],
                              }, [""]]},
                           "http://subdomain.foo.org/" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "subdomain.foo.org",
                                "x-host" => env["http_host"] || env["server_name"],
                              }, [""]]},
                           "http://bar.org/" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "bar.org",
                                "x-host" => env["http_host"] || env["server_name"],
                              }, [""]]},
                           "/" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "default.org",
                                "x-host" => env["http_host"] || env["server_name"],
                              }, [""]]}
                           ))

    res = Rack::MockRequest.new(map).get("/")
    res.must_be :ok?
    res["x-position"].must_equal "default.org"

    res = Rack::MockRequest.new(map).get("/", "http_host" => "bar.org")
    res.must_be :ok?
    res["x-position"].must_equal "bar.org"

    res = Rack::MockRequest.new(map).get("/", "http_host" => "foo.org")
    res.must_be :ok?
    res["x-position"].must_equal "foo.org"

    res = Rack::MockRequest.new(map).get("/", "http_host" => "subdomain.foo.org", "server_name" => "foo.org")
    res.must_be :ok?
    res["x-position"].must_equal "subdomain.foo.org"

    res = Rack::MockRequest.new(map).get("http://foo.org/")
    res.must_be :ok?
    res["x-position"].must_equal "foo.org"

    res = Rack::MockRequest.new(map).get("/", "http_host" => "example.org")
    res.must_be :ok?
    res["x-position"].must_equal "default.org"

    res = Rack::MockRequest.new(map).get("/",
                                         "http_host" => "example.org:9292",
                                         "server_port" => "9292")
    res.must_be :ok?
    res["x-position"].must_equal "default.org"
  end

  it "be nestable" do
    map = Rack::Lint.new(Rack::URLMap.new("/foo" =>
      Rack::URLMap.new("/bar" =>
        Rack::URLMap.new("/quux" =>  lambda { |env|
                           [200,
                            { "content-type" => "text/plain",
                              "x-position" => "/foo/bar/quux",
                              "x-pathinfo" => env["path_info"],
                              "x-scriptname" => env["script_name"],
                            }, [""]]}
                         ))))

    res = Rack::MockRequest.new(map).get("/foo/bar")
    res.must_be :not_found?

    res = Rack::MockRequest.new(map).get("/foo/bar/quux")
    res.must_be :ok?
    res["x-position"].must_equal "/foo/bar/quux"
    res["x-pathinfo"].must_equal ""
    res["x-scriptname"].must_equal "/foo/bar/quux"
  end

  it "route root apps correctly" do
    map = Rack::Lint.new(Rack::URLMap.new("/" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "root",
                                "x-pathinfo" => env["path_info"],
                                "x-scriptname" => env["script_name"]
                              }, [""]]},
                           "/foo" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "foo",
                                "x-pathinfo" => env["path_info"],
                                "x-scriptname" => env["script_name"]
                              }, [""]]}
                           ))

    res = Rack::MockRequest.new(map).get("/foo/bar")
    res.must_be :ok?
    res["x-position"].must_equal "foo"
    res["x-pathinfo"].must_equal "/bar"
    res["x-scriptname"].must_equal "/foo"

    res = Rack::MockRequest.new(map).get("/foo")
    res.must_be :ok?
    res["x-position"].must_equal "foo"
    res["x-pathinfo"].must_equal ""
    res["x-scriptname"].must_equal "/foo"

    res = Rack::MockRequest.new(map).get("/bar")
    res.must_be :ok?
    res["x-position"].must_equal "root"
    res["x-pathinfo"].must_equal "/bar"
    res["x-scriptname"].must_equal ""

    res = Rack::MockRequest.new(map).get("")
    res.must_be :ok?
    res["x-position"].must_equal "root"
    res["x-pathinfo"].must_equal "/"
    res["x-scriptname"].must_equal ""
  end

  it "not squeeze slashes" do
    map = Rack::Lint.new(Rack::URLMap.new("/" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "root",
                                "x-pathinfo" => env["path_info"],
                                "x-scriptname" => env["script_name"]
                              }, [""]]},
                           "/foo" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "foo",
                                "x-pathinfo" => env["path_info"],
                                "x-scriptname" => env["script_name"]
                              }, [""]]}
                           ))

    res = Rack::MockRequest.new(map).get("/http://example.org/bar")
    res.must_be :ok?
    res["x-position"].must_equal "root"
    res["x-pathinfo"].must_equal "/http://example.org/bar"
    res["x-scriptname"].must_equal ""
  end

  it "not be case sensitive with hosts" do
    map = Rack::Lint.new(Rack::URLMap.new("http://example.org/" => lambda { |env|
                             [200,
                              { "content-type" => "text/plain",
                                "x-position" => "root",
                                "x-pathinfo" => env["path_info"],
                                "x-scriptname" => env["script_name"]
                              }, [""]]}
                           ))

    res = Rack::MockRequest.new(map).get("http://example.org/")
    res.must_be :ok?
    res["x-position"].must_equal "root"
    res["x-pathinfo"].must_equal "/"
    res["x-scriptname"].must_equal ""

    res = Rack::MockRequest.new(map).get("http://EXAMPLE.ORG/")
    res.must_be :ok?
    res["x-position"].must_equal "root"
    res["x-pathinfo"].must_equal "/"
    res["x-scriptname"].must_equal ""
  end
end
