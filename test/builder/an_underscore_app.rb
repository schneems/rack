class AnUnderscoreApp
  def self.call(env)
    [200, {'content-type' => 'text/plain'}, ['OK']]
  end
end
