# frozen_string_literal: true

module Repositories
  # A finder class for getting the tag of the last release before a given
  # version, used when generating changelogs.
  #
  # Imagine a project with the following tags:
  #
  # * v1.0.0
  # * v1.1.0
  # * v2.0.0
  #
  # If the version supplied is 2.1.0, the tag returned will be v2.0.0. And when
  # the version is 1.1.1, or 1.2.0, the returned tag will be v1.1.0.
  #
  # To obtain the tags, this finder requires a regular expression (using the re2
  # syntax) to be provided. This regex must produce the following named
  # captures:
  #
  # - major (required)
  # - minor (required)
  # - patch (required)
  # - pre
  # - meta
  #
  # If the `pre` group has a value, the tag is ignored. If any of the required
  # capture groups don't have a value, the tag is also ignored.
  class ChangelogTagFinder
    def initialize(project, regex: Gitlab::Changelog::Config::DEFAULT_TAG_REGEX)
      @project = project
      @regex = regex
    end

    def execute(new_version)
      tags = {}

      requested_version = extract_version(new_version)
      return unless requested_version

      versions = [requested_version]

      @project.repository.tags.each do |tag|
        version = extract_version(tag.name)

        next unless version

        tags[version] = tag
        versions << version
      end

      VersionSorter.sort!(versions)

      index = versions.index(requested_version)

      tags[versions[index - 1]] if index&.positive?
    end

    private

    def version_matcher
      @version_matcher ||= Gitlab::UntrustedRegexp.new(@regex)
    rescue RegexpError => e
      # The error messages produced by default are not very helpful, so we
      # raise a better one here. We raise the specific error here so its
      # message is displayed in the API (where we catch this specific
      # error).
      raise(
        Gitlab::Changelog::Error,
        "The regular expression to use for finding the previous tag for a version is invalid: #{e.message}"
      )
    end

    def extract_version(string)
      matches = version_matcher.match(string)

      return unless matches

      # When using this class for generating changelog data for a range of
      # commits, we want to compare against the tag of the last _stable_
      # release; not some random RC that came after that.
      return if matches[:pre]

      major = matches[:major]
      minor = matches[:minor]
      patch = matches[:patch]
      build = matches[:meta]

      return unless major && minor && patch

      version = "#{major}.#{minor}.#{patch}"
      version += "+#{build}" if build

      version
    end
  end
end
