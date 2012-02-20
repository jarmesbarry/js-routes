class JsRoutes

  #
  # OPTIONS
  #

  DEFAULT_PATH = File.join('app','assets','javascripts','routes.js')

  DEFAULTS = {
    :namespace => "Routes",
    :default_format => "",
    :exclude => [],
    :include => //,
    :file => DEFAULT_PATH,
    :prefix => ""
  }

  class Options < Struct.new(*DEFAULTS.keys)
    def to_hash
      Hash[*members.zip(values).flatten(1)].symbolize_keys
    end
  end

  #
  # API
  #

  class << self
    def setup(&block)
      options.tap(&block) if block
    end

    def options
      @options ||= Options.new.tap do |opts|
        DEFAULTS.each_pair {|k,v| opts[k] = v}
      end
    end

    def generate(opts = {})
      new(opts).generate
    end

    def generate!(file_name, opts = {})
      if file_name.is_a?(Hash)
        opts = file_name
        file_name = opts[:file]
      end
      new(opts).generate!(file_name)
    end

    # Under rails 3.1.1 and higher, perform a check to ensure that the
    # full environment will be available during asset compilation.
    # This is required to ensure routes are loaded.
    def assert_usable_configuration!
      unless Rails.application.config.assets.initialize_on_precompile 
        raise("Cannot precompile js-routes unless environment is initialized. Please set config.assets.initialize_on_precompile to true.")
      end
      true
    end
  end

  #
  # Implementation
  #

  def initialize(options = {})
    @options = self.class.options.to_hash.merge(options)
  end

  def generate
    js = File.read(File.dirname(__FILE__) + "/routes.js")
    js.gsub!("NAMESPACE", @options[:namespace])
    js.gsub!("DEFAULT_FORMAT", @options[:default_format].to_s)
    js.gsub!("PREFIX", @options[:prefix])
    js.gsub!("ROUTES", js_routes)
  end

  def generate!(file_name)
    # Some libraries like Devise do not yet loaded their routes so we will wait
    # until initialization process finish
    # https://github.com/railsware/js-routes/issues/7
    Rails.configuration.after_initialize do
      File.open(Rails.root.join(file_name || DEFAULT_PATH), 'w') do |f|
        f.write generate
      end
    end
  end

  protected

  def js_routes
    Rails.application.reload_routes!
    js_routes = Rails.application.routes.named_routes.routes.map do |_, route|
      if any_match?(route, @options[:exclude]) || !any_match?(route, @options[:include])
        nil
      else
        build_js(route)
      end
    end.compact

    "{\n" + js_routes.join(",\n") + "}\n"
  end

  def any_match?(route, matchers)
    matchers = Array(matchers)
    matchers.any? {|regex| route.name =~ regex}
  end

  def build_js(route)
    params = build_params route
    _ = <<-JS.strip!
  // #{route.name} => #{route.path.spec}
  #{route.name}_path: function(#{(params + ["options"]).join(", ")}) {
  return Utils.build_path(#{json(route.required_parts.map(&:to_s))}, #{json(serialize(route.path.spec))}, arguments)
  }
  JS
  end

  def json(string)
    ActiveSupport::JSON.encode(string)
  end

  def build_params route
    route.required_parts.map do |name|
      # prepending each parameter name with underscore
      # to prevent conflict with JS reserved words
      "_" + name.to_s
    end
  end

  def serialize(spec)
    return nil unless spec
    return spec.tr(':', '') if spec.is_a?(String)
    [      
      spec.type.to_s,
      serialize(spec.left),
      spec.respond_to?(:right) && serialize(spec.right)
    ]
  end
end
