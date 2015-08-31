require 'minitest/autorun'
require 'thread'
require 'rack/lint'
require 'rack/mock'
require 'rack/session/pool'

describe Rack::Session::Pool do
  session_key = Rack::Session::Pool::DEFAULT_OPTIONS[:key]
  session_match = /#{session_key}=[0-9a-fA-F]+;/

  incrementor = lambda do |env|
    env["rack.session"]["counter"] ||= 0
    env["rack.session"]["counter"] += 1
    Rack::Response.new(env["rack.session"].inspect).to_a
  end

  session_id = Rack::Lint.new(lambda do |env|
    Rack::Response.new(env["rack.session"].inspect).to_a
  end)

  nothing = Rack::Lint.new(lambda do |env|
    Rack::Response.new("Nothing").to_a
  end)

  drop_session = Rack::Lint.new(lambda do |env|
    env['rack.session.options'][:drop] = true
    incrementor.call(env)
  end)

  renew_session = Rack::Lint.new(lambda do |env|
    env['rack.session.options'][:renew] = true
    incrementor.call(env)
  end)

  defer_session = Rack::Lint.new(lambda do |env|
    env['rack.session.options'][:defer] = true
    incrementor.call(env)
  end)

  incrementor = Rack::Lint.new(incrementor)

  it "creates a new cookie" do
    pool = Rack::Session::Pool.new(incrementor)
    res = Rack::MockRequest.new(pool).get("/")
    res["set-cookie"].must_match(session_match)
    res.body.must_equal '{"counter"=>1}'
  end

  it "determines session from a cookie" do
    pool = Rack::Session::Pool.new(incrementor)
    req = Rack::MockRequest.new(pool)
    cookie = req.get("/")["Set-Cookie"]
    req.get("/", "http_cookie" => cookie).
      body.must_equal '{"counter"=>2}'
    req.get("/", "http_cookie" => cookie).
      body.must_equal '{"counter"=>3}'
  end

  it "survives nonexistant cookies" do
    pool = Rack::Session::Pool.new(incrementor)
    res = Rack::MockRequest.new(pool).
      get("/", "http_cookie" => "#{session_key}=blarghfasel")
    res.body.must_equal '{"counter"=>1}'
  end

  it "does not send the same session id if it did not change" do
    pool = Rack::Session::Pool.new(incrementor)
    req = Rack::MockRequest.new(pool)

    res0 = req.get("/")
    cookie = res0["set-cookie"][session_match]
    res0.body.must_equal '{"counter"=>1}'
    pool.pool.size.must_equal 1

    res1 = req.get("/", "http_cookie" => cookie)
    res1["Set-Cookie"].must_be_nil
    res1.body.must_equal '{"counter"=>2}'
    pool.pool.size.must_equal 1

    res2 = req.get("/", "http_cookie" => cookie)
    res2["set-cookie"].must_be_nil
    res2.body.must_equal '{"counter"=>3}'
    pool.pool.size.must_equal 1
  end

  it "deletes cookies with :drop option" do
    pool = Rack::Session::Pool.new(incrementor)
    req = Rack::MockRequest.new(pool)
    drop = Rack::Utils::Context.new(pool, drop_session)
    dreq = Rack::MockRequest.new(drop)

    res1 = req.get("/")
    session = (cookie = res1["set-cookie"])[session_match]
    res1.body.must_equal '{"counter"=>1}'
    pool.pool.size.must_equal 1

    res2 = dreq.get("/", "http_cookie" => cookie)
    res2["set-cookie"].must_be_nil
    res2.body.must_equal '{"counter"=>2}'
    pool.pool.size.must_equal 0

    res3 = req.get("/", "http_cookie" => cookie)
    res3["set-cookie"][session_match].wont_equal session
    res3.body.must_equal '{"counter"=>1}'
    pool.pool.size.must_equal 1
  end

  it "provides new session id with :renew option" do
    pool = Rack::Session::Pool.new(incrementor)
    req = Rack::MockRequest.new(pool)
    renew = Rack::Utils::Context.new(pool, renew_session)
    rreq = Rack::MockRequest.new(renew)

    res1 = req.get("/")
    session = (cookie = res1["set-cookie"])[session_match]
    res1.body.must_equal '{"counter"=>1}'
    pool.pool.size.must_equal 1

    res2 = rreq.get("/", "http_cookie" => cookie)
    new_cookie = res2["set-cookie"]
    new_session = new_cookie[session_match]
    new_session.wont_equal session
    res2.body.must_equal '{"counter"=>2}'
    pool.pool.size.must_equal 1

    res3 = req.get("/", "http_cookie" => new_cookie)
    res3.body.must_equal '{"counter"=>3}'
    pool.pool.size.must_equal 1

    res4 = req.get("/", "http_cookie" => cookie)
    res4.body.must_equal '{"counter"=>1}'
    pool.pool.size.must_equal 2
  end

  it "omits cookie with :defer option" do
    pool = Rack::Session::Pool.new(incrementor)
    defer = Rack::Utils::Context.new(pool, defer_session)
    dreq = Rack::MockRequest.new(defer)

    res1 = dreq.get("/")
    res1["set-cookie"].must_equal nil
    res1.body.must_equal '{"counter"=>1}'
    pool.pool.size.must_equal 1
  end

  # anyone know how to do this better?
  it "should merge sessions when multithreaded" do
    unless $DEBUG
      1.must_equal 1
      next
    end

    warn 'Running multithread tests for Session::Pool'
    pool = Rack::Session::Pool.new(incrementor)
    req = Rack::MockRequest.new(pool)

    res = req.get('/')
    res.body.must_equal '{"counter"=>1}'
    cookie = res["set-cookie"]
    sess_id = cookie[/#{pool.key}=([^,;]+)/,1]

    delta_incrementor = lambda do |env|
      # emulate disconjoinment of threading
      env['rack.session'] = env['rack.session'].dup
      Thread.stop
      env['rack.session'][(Time.now.usec*rand).to_i] = true
      incrementor.call(env)
    end
    tses = Rack::Utils::Context.new pool, delta_incrementor
    treq = Rack::MockRequest.new(tses)
    tnum = rand(7).to_i+5
    r = Array.new(tnum) do
      Thread.new(treq) do |run|
        run.get('/', "http_cookie" => cookie, 'rack.multithread' => true)
      end
    end.reverse.map{|t| t.run.join.value }
    r.each do |resp|
      resp['set-cookie'].must_equal cookie
      resp.body.must_include '"counter"=>2'
    end

    session = pool.pool[sess_id]
    session.size.must_equal tnum+1 # counter
    session['counter'].must_equal 2 # meeeh
  end

  it "does not return a cookie if cookie was not read/written" do
    app = Rack::Session::Pool.new(nothing)
    res = Rack::MockRequest.new(app).get("/")
    res["set-cookie"].must_be_nil
  end

  it "does not return a cookie if cookie was not written (only read)" do
    app = Rack::Session::Pool.new(session_id)
    res = Rack::MockRequest.new(app).get("/")
    res["set-cookie"].must_be_nil
  end

  it "returns even if not read/written if :expire_after is set" do
    app = Rack::Session::Pool.new(nothing, :expire_after => 3600)
    res = Rack::MockRequest.new(app).get("/", 'rack.session' => {'not' => 'empty'})
    res["set-cookie"].wont_be :nil?
  end

  it "returns no cookie if no data was written and no session was created previously, even if :expire_after is set" do
    app = Rack::Session::Pool.new(nothing, :expire_after => 3600)
    res = Rack::MockRequest.new(app).get("/")
    res["set-cookie"].must_be_nil
  end
end
