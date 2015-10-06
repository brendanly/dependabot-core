require "gemnasium/parser"
require "bumper/dependency_file"
require "tmpdir"
require "bundler"

module DependencyFileUpdaters
  # NOTE: in ruby a requirement is a matcher and version
  # e.g. "~> 1.2.3", where "~>" is the match
  class RubyDependencyFileUpdater
    attr_reader :gemfile, :gemfile_lock, :dependency

    BUMP_TMP_FILE_PREFIX = "bump_".freeze
    BUMP_TMP_DIR_PATH = "tmp".freeze

    def initialize(dependency_files:, dependency:)
      @gemfile = dependency_files.find { |f| f.name == "Gemfile" }
      @gemfile_lock = dependency_files.find { |f| f.name == "Gemfile.lock" }
      validate_files_are_present!

      @dependency = dependency
    end

    def updated_dependency_files
      return @updated_dependency_files if @updated_dependency_files

      @updated_dependency_files = [
        DependencyFile.new(
          name: "Gemfile",
          content: updated_gemfile_content
        ),
        DependencyFile.new(
          name: "Gemfile.lock",
          content: updated_gemfile_lock_content
        )
      ]
    end

    private

    def validate_files_are_present!
      raise "No Gemfile!" unless gemfile
      raise "No Gemfile.lock!" unless gemfile_lock
    end

    def updated_gemfile_content
      return @updated_gemfile_content if @updated_gemfile_content

      gemfile.content.
        to_enum(:scan, Gemnasium::Parser::Patterns::GEM_CALL).
        find { Regexp.last_match[:name] == dependency.name }

      original_gem_declaration_string = $&
      updated_gem_declaration_string =
        original_gem_declaration_string.sub(/[\d\.]+/, dependency.version)

      @updated_gemfile_content = gemfile.content.gsub(
        original_gem_declaration_string,
        updated_gem_declaration_string
      )
    end

    def updated_gemfile_lock_content
      return @updated_gemfile_lock_content if @updated_gemfile_lock_content

      in_a_temporary_directory do |dir|
        File.write(File.join(dir, "Gemfile"), updated_gemfile_content)
        File.write(File.join(dir, "Gemfile.lock"), gemfile_lock.content)
        Bundler.with_clean_env do
          Bundler::SharedHelpers.chdir(dir) do
            definition = Bundler.definition(gems: [dependency.name])
            definition.resolve_remotely!
            @updated_gemfile_lock_content = definition.to_lock
          end
        end
      end

      @updated_gemfile_lock_content
    end

    def in_a_temporary_directory
      Dir.mkdir(BUMP_TMP_DIR_PATH) unless Dir.exist?(BUMP_TMP_DIR_PATH)
      Dir.mktmpdir(BUMP_TMP_FILE_PREFIX, BUMP_TMP_DIR_PATH) do |dir|
        yield dir
      end
    end
  end
end
