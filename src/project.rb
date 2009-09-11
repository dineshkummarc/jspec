
module JSpec
  
  #--
  # Base project
  #++
  
  class Project
    
    #--
    # Constants
    #++
    
    BIND_PATHS = 'lib/**/*.js', 'spec/**/*.js'
    RHINO = 'java org.mozilla.javascript.tools.shell.Main'
    
    ##
    # Destination directory.
    
    attr_reader :dest
    
    ##
    # Initialize project with _dest_.
    
    def initialize dest
      @dest = dest || '.'
    end
    
    ##
    # Execute _file_ with Rhino.

    def rhino file
      system "#{RHINO} #{file}"
    end
    
    ##
    # Install project _name_ with _options_.
    
    def install name, options = {}
      raise ArgumentError, ':to option required' unless options.include? :to
      project = JSpec::Installable.const_get(name.downcase.capitalize).new options
      if project.use_progress_bar?
        progress [:before, :install, :after], 
          :complete_message => project.install_message,
          :format => "Installing #{name} (:progress_bar) %:percent_complete" do |method|
          project.send method
        end
      else
        project.before
        project.install
        project.after
        say project.install_message
      end
    end
    
    ##
    # Initialize the project with _options_

    def init! options = {}
      verify_empty!
      copy_template :default
      vendorize_with_symlink if options.include? :symlink
      vendorize_with_copy if options.include? :freeze
      replace_root
    end
    
    ##
    # Vendorize JSpec with symlink.
    
    def vendorize_with_symlink
      FileUtils.symlink "#{JSPEC_ROOT}/lib", normalize('lib'), :force => true
    end
    
    ##
    # Vendorize JSpec with copy.
    
    def vendorize_with_copy
      FileUtils.cp_r "#{JSPEC_ROOT}/lib", normalize('lib')
    end
    
    ##
    # Copy template _name_ to the destination.
    
    def copy_template name, options = {}
      FileUtils.mkdir_p dest
      FileUtils.cp_r path_to_template(name), options[:to] ?
        "#{dest}/#{options[:to]}" :
          dest
    end
    
    ##
    # Normalize _path_.
    
    def normalize path
      "#{dest}/spec/#{path}"
    end
    
    ##
    # Check if we are working with vendorized JSpec.
    
    def vendorized?
      File.directory?(normalize(:lib)) && normalize(:lib)
    end
    
    ##
    # Replace absolute JSPEC_ROOT paths.
    
    def replace_root
      replace_root_in 'environments/dom.html', 'environments/rhino.js'
    end
    
    ##
    # Root JSpec directory.
    
    def root
      vendorized? ? './spec' : JSPEC_ROOT
    end
    
    ##
    # Replace absolute JSPEC_ROOT _paths_.
    
    def replace_root_in *paths
      paths.each do |path|
        contents = File.read(normalize(path)).gsub 'JSPEC_ROOT', root
        File.open(normalize(path), 'w') { |file| file.write contents }
      end
    end
    
    ##
    # Path to template _name_.
    
    def path_to_template name
      "#{JSPEC_ROOT}/templates/#{name}/."
    end
    
    ##
    # Verify that the current directory is empty, otherwise 
    # prompt for continuation.
    
    def verify_empty!
      unless Dir[dest + '/*'].empty?
        abort unless agree "`#{dest}' is not empty; continue? "
      end
    end
    
    ##
    # Update absolute paths and/or vendorized libraries.
    
    def update!
      if path = vendorized?
        type = File.symlink?(path) ? :symlink : :copy
        FileUtils.rm_rf normalize(:lib)
        send "vendorize_with_#{type}"
        say "updated #{type} #{path} -> #{program(:version)}"
      else
        ['environments/dom.html', 'environments/rhino.js'].each do |path|
          path = normalize path
          next unless File.exists? path
          contents = File.read(path).gsub /visionmedia-jspec-(\d+\.\d+\.\d+)/, "visionmedia-jspec-#{program(:version)}"
          if program(:version) == $1
            say "skipping #{path}; already #{$1}"
            next
          end
          File.open(path, 'r+'){ |file| file.write contents } 
          say "updated #{path}; #{$1} -> #{program(:version)}"
        end
      end
    end
    
    ##
    # Start server with _path_ html and _options_.

    def start_server path, options = {}
      options[:port] ||= 4444
      set :port, options[:port]
      set :server, 'Mongrel'
      enable :sessions
      disable :logging
      hook = File.expand_path normalize('environments/server.rb')
      load hook if File.exists? hook
      browsers = browsers_for(options[:browsers]) if options.include? :browsers
      JSpec::Server.new(path, options[:port]).start(browsers)
    end

    ##
    # Return array of browser instances for the given _names_.

    def browsers_for names
      names.map do |name|
        begin
          Browser.subclasses.find do |browser|
            browser.matches_name? name
          end.new
        rescue
          raise "Unsupported browser `#{name}'"
        end
      end
    end
    
    ##
    # Run _path_ with _options_.
    
    def run! path = nil, options = {}
      paths = options[:paths] || self.class::BIND_PATHS

      # Action
      
      case
      when options.include?(:rhino)
        path ||= normalize('environments/rhino.js')
        action = lambda { rhino path }
      when options.include?(:server)
        raise 'Cannot use --bind with --server' if options.include? :bind
        path ||= normalize('environments/server.html')
        action = lambda { start_server path, options }
      else
        path ||= normalize('environments/dom.html')
        browsers = browsers_for options[:browsers] || ['safari']
        action = lambda do
          browsers.each do |browser|
            browser.visit File.expand_path(path)
          end
        end
      end 
      
      # Bind action
      
      if options.include? :bind
        Bind::Listener.new(
          :paths => paths,
          :interval => 1,
          :actions => [action],
          :debug => $stdout).run!
      else
        action.call File.new(path)
      end
    end
    
    ##
    # Return the Project instance which should be used for _dest_. 
    
    def self.for dest
      (File.directory?("#{dest}/vendor") ? 
        JSpec::Project::Rails : 
          JSpec::Project).new(dest)
    end
    
    #--
    # Rails project
    #++
    
    class Rails < self
      
      #--
      # Constants
      #++
      
      BIND_PATHS = 'public/javascripts/**/*.js', 'jspec/**/*.js'
      
      ##
      # Initialize the project with _options_

      def init! options = {}
        verify_rails!
        copy_template :rails, :to => :jspec
        vendorize_with_symlink if options.include? :symlink
        vendorize_with_copy if options.include? :freeze
        replace_root
      end
      
      ##
      # Root JSpec directory.

      def root
        vendorized? ? './jspec' : JSPEC_ROOT
      end
      
      ##
      # Normalize _path_.

      def normalize path
        "#{dest}/jspec/#{path}"
      end
      
      ##
      # Verify that the current directory is rails, otherwise 
      # prompt for continuation.

      def verify_rails!
        unless rails?
          abort unless agree "`#{dest}' does not appear to be a rails app; continue? "
        end
      end
      
      ##
      # Check if the destination is the root of 
      # a rails application.
      
      def rails?
        File.directory? dest + '/vendor'
      end
      
    end
    
  end
end
