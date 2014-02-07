require 'aws-sdk'
require 'trollop'

require 'opsworks'

SSH_PREFIX  = "# --- OpsWorks ---"
SSH_POSTFIX = "# --- End of OpsWorks ---"

module OpsWorks::Commands
  class SSH
    def self.banner
      "Generate and update SSH configuration files"
    end

    def self.run
      options = Trollop::options do
        banner <<-EOS.unindent
          #{SSH.banner}

          Options:
        EOS
        opt :update, "Update ~/.ssh/config directly"
        opt :backup, "Backup old SSH config before updating"
        opt :quiet,  "Use SSH LogLevel quiet", default: true
        opt :key_checking,
            "Check SSH host keys (this can be annoying since dynamic " <<
            "instances often change IP number)", short: 'c', default: false
      end

      config = OpsWorks.config
      client = AWS::OpsWorks::Client.new

      stacks     = []
      stack_data = client.describe_stacks
      stack_data[:stacks].each { |stack| stacks << stack[:stack_id] }

      stacks.each do |stack_id|
        instances   = []
        stack_name  = ''

        stack_details = client.describe_stacks(stack_ids: [stack_id])
        stack_details[:stacks].each { |stack| stack_name = stack[:name].gsub('::','-') }

        result = client.describe_instances(stack_id: stack_id)
        instances += result.instances.select { |i| i[:status] != "stopped" }

        #instances.reject! { |i| i[:elastic_ip].nil? && i[:public_ip].nil? }
        instances.map! do |instance|
          ip = instance[:private_ip] #|| instance[:public_ip]
          parameters = {
            "Host"                  => "#{instance[:hostname]}-#{stack_name}",
            "HostName"              => ip,
            "User"                  => config.ssh_user_name,
          }
          #parameters.merge!({
          #  "StrictHostKeyChecking" => "no",
          #  "UserKnownHostsFile"    => "/dev/null",
          #}) unless options[:host_checking]
          parameters["LogLevel"] = "quiet" if options[:quiet]
          parameters.map{ |param| param.join(" ") }.join("\n  ")
        end
  
        new_contents = "#{instances.join("\n")}\n"
                      
        #new_contents = "\n\n#{SSH_PREFIX}\n" <<
                      #"#{instances.join("\n")}\n" <<
                      #"#{SSH_POSTFIX}\n\n"
  
        if options[:update]
          ssh_config = "#{ENV['HOME']}/.ssh/config"
          old_contents = File.read(ssh_config)

          if options[:backup]
            base_name = ssh_config + ".backup"
            if File.exists? base_name
              number = 0
              file_name = "#{base_name}-#{number}"
              while File.exists? file_name
                file_name = "#{base_name}-#{number += 1}"
              end
            else
              file_name = base_name
            end
            File.open(file_name, "w") { |file| file.puts old_contents }
          end

          File.open(ssh_config, "w") do |file|
            file.puts old_contents.gsub(
              /\n?\n?#{SSH_PREFIX}.*#{SSH_POSTFIX}\n?\n?/m,
              ''
            )
            file.puts new_contents
          end

          puts "Successfully updated #{ssh_config} with " <<
              "#{instances.length} instances!"
        else
          puts new_contents.strip
        end
      end
    end
  end
end
