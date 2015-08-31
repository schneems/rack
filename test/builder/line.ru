run lambda{ |env| [200, {'content-type' => 'text/plain'}, [__LINE__.to_s]] }
