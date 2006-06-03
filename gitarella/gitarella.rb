# Gitarella - web interface for GIT
# Copyright (c) 2006 Diego "Flameeyes" Pettenò <flameeyes@gentoo.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require "cgi"
require "yaml"
require "filemagic"
require "liquid"
require "pathname"

require "gitarella/gitrepo"
require "gitarella/gitutils"
require "gitarella/project_show"
require "gitarella/tree_browse"

$config = YAML::load(File.new("gitarella-config.yml").read)

$memcache = nil

if $config["memcache-servers"] and not $config["memcache-servers"].empty?
   require "memcache"
   $memcache = MemCache::new($config["memcache-servers"], :namespace => 'gitarella', :compression => 'true')
end

module Gitarella
   class GitarellaCGI
      attr_reader :path

      @@repos = Hash.new

      def GitarellaCGI.init_repos
         @@repos = Hash.new

         $config["repositories"].each { |repo|
            gitrepo = GITRepo.new(repo)
            @@repos[gitrepo.id] = gitrepo
         }
      end

      def initialize(cgi)
         @cgi = cgi
         @path = cgi.path_info.split(/\/+/).delete_if { |x| x.empty? }

         # Rule out the static files immediately
         return static_file(".#{cgi.path_info}") if @path[0] == "static"

         @template_params = {
            "basepath" => cgi.script_name,
            "currpath" => cgi.script_name + cgi.path_info
         }

         @content = ""

         case path.size
            when 0 then project_list
            when 1 then project_show
            else tree_browse
         end

         @template_params["content"] = @content
         @cgi.out {
            Liquid::Template.parse( File.open("templates/main.liquid").read ).render(@template_params)
         }
      end

      def project_list
         @template_params["repositories"] = Array.new
         @@repos.each_value { |gitrepo|
            next unless gitrepo.valid
            @template_params["repositories"] << gitrepo.to_hash
         }

         @template_params["sort"] = @cgi.has_key?("sort") ? @cgi["sort"] : "id"
         @template_params["sort"] = "id" if not @template_params["repositories"][0].has_key?(@template_params["sort"])
         @template_params["repositories"].sort! { |x, y| x[@template_params["sort"]] <=> y[@template_params["sort"]] }

         @template_params["title"] = "gitarella - browse projects"
         @content = Liquid::Template.parse( File.open("templates/projects.liquid").read ).render(@template_params)
      end

      def static_file(path)
            staticfile = File.open(path)
            staticmime = FileMagic.new(FileMagic::MAGIC_MIME|FileMagic::MAGIC_SYMLINK).file(path)
            @cgi.out({ "content-type" => staticmime}) { staticfile.read }
            return nil
      end

      def get_repo_id
         @repo_id = @path[0]; @path.delete_at(0)
         return @cgi.out({"status" => CGI::HTTP_STATUS["NOT_FOUND"]}) { "Repository not found" } \
            if not @@repos.has_key?(@repo_id)

         $stderr.puts @@repos[@repo_id].inspect
         @commit_hash = (@cgi.has_key?("h") and not @cgi["h"].empty?) ? @cgi["h"] : @@repos[@repo_id].sha1_head
         $stderr.puts @commit_hash

         @template_params["title"] = "gitarella - #{@repo_id}"
         @template_params["commit_hash"] = @commit_hash
         @template_params["commit_desc"] = @@repos[@repo_id].commit(@commit_hash).description
         @template_params["files_list"] = @@repos[@repo_id].list
         @template_params["repository"] = @@repos[@repo_id].to_hash
      end
   end

   def handle(cgi)
      GitarellaCGI.new(cgi)
   end
end

# kate: encoding UTF-8; remove-trailing-space on; replace-trailing-space-save on; space-indent on; indent-width 3;
