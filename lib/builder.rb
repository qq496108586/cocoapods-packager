module Pod
  class Builder
    def initialize(source_dir, sandbox_root, public_headers_root, spec, embedded)
      @source_dir = source_dir
      @sandbox_root = sandbox_root
      @public_headers_root = public_headers_root
      @spec = spec
      @embedded = embedded
    end

    def build_framework(platform)
      defines = compile
      create_framework(platform.name.to_s)
      copy_headers
      build_library(platform, defines)
      copy_license
      copy_resources(platform)
    end

    def link_embedded_resources
      target_path = @fwk.root_path + Pathname.new('Resources')
      target_path.mkdir unless target_path.exist?

      Dir.glob(@fwk.resources_path.to_s + '/*').each do |resource|
        resource = Pathname.new(resource).relative_path_from(target_path)
        `ln -sf #{resource} #{target_path}`
      end
    end

    :private

    def build_library(platform, defines)
      output = @fwk.versions_path + Pathname.new(@spec.name)
      static_libs = static_libs_in_sandbox

      if platform.name == :ios
        build_static_lib_for_ios(static_libs, defines, output)
      else
        build_static_lib_for_mac(static_libs, output)
      end
    end

    def build_static_lib_for_ios(static_libs, defines, output)
      `libtool -static -o #{@sandbox_root}/build/package.a #{static_libs.join(' ')}`

      xcodebuild(defines, '-sdk iphonesimulator', 'build-sim')
      sim_libs = static_libs.map { |path| "#{@sandbox_root}/build-sim/#{File.basename(path)}" }
      `libtool -static -o #{@sandbox_root}/build-sim/package.a #{sim_libs.join(' ')}`

      `lipo #{@sandbox_root}/build/package.a #{@sandbox_root}/build-sim/libPods.a -create -output #{output}`
    end

    def build_static_lib_for_mac(static_libs, output)
      `libtool -static -o #{output} #{static_libs.join(' ')}`
    end

    def build_with_mangling(defines)
      UI.puts 'Mangling symbols'
      defines = Symbols.mangle_for_pod_dependencies(@spec.name, @sandbox_root)
      UI.puts 'Building mangled framework'
      xcodebuild(defines)
    end

    def compile
      UI.puts 'Building framework'

      if @spec.dependencies.count > 0 && @mangle
        xcodebuild
        build_with_mangling(defines)
        defines
      end

      xcodebuild
      nil
    end

    def copy_headers
      headers_source_root = "#{@public_headers_root}/#{@spec.name}"

      Dir.glob("#{headers_source_root}/**/*.h").
        each { |h| `ditto #{h} #{@fwk.headers_path}/#{h.sub(headers_source_root, '')}` }
    end

    def copy_license
      license_file = @spec.license[:file]
      license_file = 'LICENSE' unless license_file
      `cp "#{@sandbox_root}/#{@spec.name}/#{license_file}" .`
    end

    def copy_resources(platform)
      `cp -rp #{@sandbox_root}/build/*.bundle #{@fwk.resources_path} 2>&1`

      resources = expand_paths(@spec.consumer(platform).resources)
      return if resources.count == 0
      `cp -rp #{resources.join(' ')} #{@fwk.resources_path}`
    end

    def create_framework(platform)
      @fwk = Framework::Tree.new(@spec.name, platform, @embedded)
      @fwk.make
    end

    def expand_paths(path_specs)
      paths = []

      path_specs.each do |path_spec|
        paths += Dir.glob(File.join(@source_dir, path_spec))
      end

      paths
    end

    def static_libs_in_sandbox
      Dir.glob("#{@sandbox_root}/build/*.a").reject { |e| e =~ /libPods\.a$/ }
    end

    def xcodebuild(defines = '', args = '', build_dir = 'build')
      `xcodebuild #{defines} CONFIGURATION_BUILD_DIR=#{build_dir} clean build #{args} -configuration Release -target Pods -project #{@sandbox_root}/Pods.xcodeproj 2>&1`
    end
  end
end