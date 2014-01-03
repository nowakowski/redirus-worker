module Redirus
  module Worker
    class AddProxy < Proxy
      include Sidekiq::Worker

      def perform_action(name, workers, type)
        params = {}
        params['name'] = name
        params['listen'] = https?(type)  ? config.https_template : config.http_template
        params['upstream'] = upstream_conf(name, workers, type)
        params['upstream_name'] = full_name(name, type)

        File.open(config_file_path(name, type), 'w') do |file|
          param_regexp = '#{\w*}'
          file.write config.config_template.gsub(/#{param_regexp}/) { |p| params[p[2..-2]] }
        end
      end

      private

      def https?(type)
        type == :https
      end

      def config_file_path(name, type)
        File.join(config.configs_path, full_name(name, type))
      end

      def upstream_conf(name, workers, type)
        "upstream #{name}_#{type} {\n#{workers_conf(workers)}\}\n"
      end

      def workers_conf(workers)
        workers.collect { |worker| "  server #{worker};\n" }.join
      end

      def config
        Redirus::Worker.config
      end

      def restart_nginx
        File.open(config.nginx_pid_file) do |file|
          pid = file.read.to_i
          Process.kill :SIGHUP, pid
        end
      end
    end
  end
end