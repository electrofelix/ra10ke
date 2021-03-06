require 'rake'
require 'rake/tasklib'
require 'ra10ke/version'
require 'ra10ke/solve'
require 'git'
require 'semverse'

module Ra10ke
  class RakeTask < ::Rake::TaskLib
    def initialize(*args)
      namespace :r10k do
        desc "Print outdated forge modules"
        task :dependencies do
          require 'r10k/puppetfile'
          require 'puppet_forge'

          PuppetForge.user_agent = "ra10ke/#{Ra10ke::VERSION}"
          puppetfile = R10K::Puppetfile.new(Dir.pwd)
          puppetfile.load!

          # ignore file allows for "don't tell me about this"
          ignore_modules = []
          if File.exist?('.r10kignore')
            ignore_modules = File.readlines('.r10kignore').each {|l| l.chomp!}
          end

          puppetfile.modules.each do |puppet_module|
            next if ignore_modules.include? puppet_module.title
            if puppet_module.class == R10K::Module::Forge
              module_name = puppet_module.title.gsub('/', '-')
              forge_version = PuppetForge::Module.find(module_name).current_release.version
              installed_version = puppet_module.expected_version
              if installed_version != forge_version
                puts "#{puppet_module.title} is OUTDATED: #{installed_version} vs #{forge_version}"
              end
            end

            if puppet_module.class == R10K::Module::Git
              # use helper; avoid `desired_ref`
              # we do not want to deal with `:control_branch`
              ref = puppet_module.version
              next unless ref

              remote = puppet_module.instance_variable_get(:@remote)
              remote_refs = Git.ls_remote(remote)

              # skip if ref is a branch
              next if remote_refs['branches'].key?(ref)

              if remote_refs['tags'].key?(ref)
                # there are too many possible versioning conventions
                # we have to be be opinionated here
                # so semantic versioning (vX.Y.Z) it is for us
                # as well as support for skipping the leading v letter
                tags = remote_refs['tags'].keys
                latest_tag = tags.map do |tag|
                  begin
                    Semverse::Version.new tag
                  rescue Semverse::InvalidVersionFormat
                    # ignore tags that do not comply to semver
                    nil
                  end
                end.select { |tag| !tag.nil? }.sort.last.to_s.downcase
                latest_ref = tags.detect { |tag| [tag.downcase, "v#{tag.downcase}"].include?(latest_tag) }
                latest_ref = 'undef (tags do not match semantic versioning)' if latest_ref.nil?
              elsif ref.match(/^[a-z0-9]{40}$/)
                # for sha just assume head should be tracked
                latest_ref = remote_refs['head'][:sha]
              else
                raise "Unable to determine ref type for #{puppet_module.title}"
              end

              puts "#{puppet_module.title} is OUTDATED: #{ref} vs #{latest_ref}" if ref != latest_ref
            end
          end
        end

        desc "Syntax check Puppetfile"
        task :syntax do
          require 'r10k/action/puppetfile/check'

          puppetfile = R10K::Action::Puppetfile::Check.new({
            :root => Dir.pwd,
            :moduledir => nil,
            :puppetfile => nil
          }, '')
          puppetfile.call
        end
      end
    end
  end
end

Ra10ke::RakeTask.new
