module Rack
  class Prerender
    require 'net/http'
    require 'active_support'

    def initialize(app, options={})
      # googlebot, yahoo, and bingbot are not in this list because
      # we support _escaped_fragment_ and want to ensure people aren't
      # penalized for cloaking.
      @crawler_user_agents = [
        # 'googlebot',
        # 'yahoo',
        # 'bingbot',
        'baiduspider',
        'facebookexternalhit',
        'twitterbot',
        'rogerbot',
        'linkedinbot',
        'embedly',
        'bufferbot',
        'quora link preview',
        'showyoubot',
        'outbrain',
        'pinterest',
        'developers.google.com/+/web/snippet',
        'slackbot'
      ]

      @extensions_to_ignore = [
        '.js',
        '.css',
        '.xml',
        '.less',
        '.png',
        '.jpg',
        '.jpeg',
        '.gif',
        '.pdf',
        '.doc',
        '.txt',
        '.ico',
        '.rss',
        '.zip',
        '.mp3',
        '.rar',
        '.exe',
        '.wmv',
        '.doc',
        '.avi',
        '.ppt',
        '.mpg',
        '.mpeg',
        '.tif',
        '.wav',
        '.mov',
        '.psd',
        '.ai',
        '.xls',
        '.mp4',
        '.m4a',
        '.swf',
        '.dat',
        '.dmg',
        '.iso',
        '.flv',
        '.m4v',
        '.torrent'
      ]

      @options = options
      @options[:whitelist] = [@options[:whitelist]] if @options[:whitelist].is_a? String
      @options[:blacklist] = [@options[:blacklist]] if @options[:blacklist].is_a? String
      @extensions_to_ignore = @options[:extensions_to_ignore] if @options[:extensions_to_ignore]
      @crawler_user_agents = @options[:crawler_user_agents] if @options[:crawler_user_agents]
      @app = app
    end


    def call(env)
      if should_show_prerendered_page(env)
        #CHECK CACHE
        generate_static_html(env)
      end

      @app.call(env)
    end


    def should_show_prerendered_page(env)
      user_agent = env['HTTP_USER_AGENT']
      buffer_agent = env['X-BUFFERBOT']
      is_requesting_prerendered_page = false

      return false if !user_agent
      return false if env['REQUEST_METHOD'] != 'GET'

      request = Rack::Request.new(env)

      is_requesting_prerendered_page = true if Rack::Utils.parse_query(request.query_string).has_key?('_escaped_fragment_')

      #if it is a bot...show prerendered page
      is_requesting_prerendered_page = true if @crawler_user_agents.any? { |crawler_user_agent| user_agent.downcase.include?(crawler_user_agent.downcase) }

      #if it is BufferBot...show prerendered page
      is_requesting_prerendered_page = true if buffer_agent

      #if it is a bot and is requesting a resource...dont prerender
      return false if @extensions_to_ignore.any? { |extension| request.path.include? extension }

      #if it is a bot and not requesting a resource and is not whitelisted...dont prerender
      return false if @options[:whitelist].is_a?(Array) && @options[:whitelist].all? { |whitelisted| !Regexp.new(whitelisted).match(request.path) }

      #if it is a bot and not requesting a resource and is not blacklisted(url or referer)...dont prerender
      if @options[:blacklist].is_a?(Array) && @options[:blacklist].any? { |blacklisted|
          blacklistedUrl = false
          blacklistedReferer = false
          regex = Regexp.new(blacklisted)

          blacklistedUrl = !!regex.match(request.path)
          blacklistedReferer = !!regex.match(request.referer) if request.referer

          blacklistedUrl || blacklistedReferer
        }
        return false
      end

      return is_requesting_prerendered_page
    end

    def generate_static_html(env)
      url = URI.parse(build_api_url(env))
      puts 'DETECTED BOT REQUEST :',url
      if url.query
        if url.query.include? '%2F'
          structure = url.query.split('%2F')
        else
          structure = url.query.split('/')
        end
        calc_true_url(url.query, env)
        structure.shift
        #UTM PATCH
        if structure[0].include? "scaped_fragment"
          structure.shift
        end

        puts "PRERENDER TRANSFORMING TO ...",'/seo/'+structure.join('/')
        env['PATH_INFO'] = '/seo/'+structure.join('/')
      end
      rescue NoMethodError
        puts "URL cant be transformed",url.query
    end
    def calc_true_url(query, env)
      if query.include? '%2F'
        if query.include? 'utm'
            env['TRUE_URL'] = url.query.gsub('%2F','/').gsub('&_escaped_fragment_=','/#!')
        else
            env['TRUE_URL'] = url.query.gsub('%2F','/').gsub('_escaped_fragment_=','#!')
        end
      else
        if query.include? 'utm'
            env['TRUE_URL'] = url.query.gsub('&_escaped_fragment_=','/#!')
        else
            env['TRUE_URL'] = url.query.gsub('_escaped_fragment_=','#!')
        end
      end
    end

    def build_api_url(env)
      new_env = env
      if env["CF-VISITOR"]
        match = /"scheme":"(http|https)"/.match(env['CF-VISITOR'])
        new_env["HTTPS"] = true and new_env["rack.url_scheme"] = "https" and new_env["SERVER_PORT"] = 443 if (match && match[1] == "https")
        new_env["HTTPS"] = false and new_env["rack.url_scheme"] = "http" and new_env["SERVER_PORT"] = 80 if (match && match[1] == "http")
      end

      if env["X-FORWARDED-PROTO"]
        new_env["HTTPS"] = true and new_env["rack.url_scheme"] = "https" and new_env["SERVER_PORT"] = 443 if env["X-FORWARDED-PROTO"].split(',')[0] == "https"
        new_env["HTTPS"] = false and new_env["rack.url_scheme"] = "http" and new_env["SERVER_PORT"] = 80 if env["X-FORWARDED-PROTO"].split(',')[0] == "http"
      end

      if @options[:protocol]
        new_env["HTTPS"] = true and new_env["rack.url_scheme"] = "https" and new_env["SERVER_PORT"] = 443 if @options[:protocol] == "https"
        new_env["HTTPS"] = false and new_env["rack.url_scheme"] = "http" and new_env["SERVER_PORT"] = 80 if @options[:protocol] == "http"
      end

      url = Rack::Request.new(new_env).url
      "#{url}"
    end

    def after_render(env, response)
      return true unless @options[:after_render]
      @options[:after_render].call(env, response)
    end
  end
end
