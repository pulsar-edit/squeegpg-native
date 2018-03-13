#!/usr/bin/env ruby

require 'octokit'
require 'optparse'
require 'json'

options = {
  :artifacts => [],
  :version_file => nil
}

opts = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} -v FILE -u ARTIFACT [-u ARTIFACT...]"
  opts.separator ""
  opts.separator "Command line flags:"

  opts.on("-u", "--upload ARTIFACT", "Upload ARTIFACT to the release.") do |artifact|
    options[:artifacts] << artifact
  end

  opts.on("-v", "--version-file FILE", "Read built versions from FILE.") do |vfile|
    options[:version_file] = vfile
  end

  opts.separator ""
  opts.separator "Environment variables:"
  opts.separator " GH_TOKEN A GitHub personal access token with release creation permissions."
end
opts.parse!

if options[:artifacts].empty?
  $stderr.puts "You must specify at least one artifact with --upload."
  $stderr.puts opts
  exit 1
end

if options[:version_file].nil?
  $stderr.puts "You must specify the location of the version file with --version-file."
  $stderr.puts opts
  exit 1
end

token = ENV['GH_TOKEN']
if token.nil? || token.empty?
  $stderr.puts "Missing GH_TOKEN. Unable to publish release."
  $stderr.puts opts
  exit 1
end

# ref = `git describe --tags --exact-match`
ref = `git describe --tags`.chomp
unless $?.success?
  $stderr.puts "Unable to identify the current tag."
  exit 1
end

body = "Release automatically generated by #{$0}.\n\n"
body << "##### GPG and library versions\n\n"
File.readlines(options[:version_file]).each do |line|
  m = line.match /([^:]+):\s+(.+)/
  next unless m
  body << "* #{m[1]}: #{m[2]}\n"
end

puts "Creating or locating the release for tag #{ref}."
client = Octokit::Client.new(access_token: ENV['GH_TOKEN'])
begin
  release = client.create_release("atom/squeegpg-native", ref, body: body)
rescue Octokit::UnprocessableEntity => e
  rbody = JSON.parse(e.response_body)
  if rbody['errors'].any? { |e| e['code'] == "already_exists" }
    puts "Release already exists."
    release = client.release_for_tag("atom/squeegpg-native", ref)
  else
    raise e
  end
end

puts "Attaching assets to release."

options[:artifacts].each do |artifact|
  print "Uploading #{artifact} ..."
  $stdout.flush
  client.upload_asset(
    release.url,
    artifact,
    name: File.basename(artifact)
  )
  puts " Complete."
end

puts "🌈 Release #{release.name} has been created."
