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

require "gitrepo"
require "gitutils"

$config = YAML::load(File.new("gitarella-config.yml").read)

$memcache = nil

if $config["memcache-servers"] and not $config["memcache-servers"].empty?
   require "memcache"
   $memcache = MemCache::new($config["memcache-servers"], :namespace => 'gitarella', :compression => 'true')
end

def handle_request(cgi)
   $stderr.puts cgi.inspect
   path = cgi.path_info.split(/\/+/).delete_if { |x| x.empty? }

   # Rule out the static files immediately
   if path[0] == "static"
      staticfile = File.open(".#{cgi.path_info}")
      staticmime = FileMagic.new(FileMagic::MAGIC_MIME|FileMagic::MAGIC_SYMLINK).file(".#{cgi.path_info}")

      cgi.out({ "content-type" => staticmime}) { staticfile.read }
      return
   end

   template_params = { "basepath" => cgi.script_name, "currpath" => cgi.script_name + cgi.path_info }
   repos = Hash.new

   $config["repositories"].each { |repo|
      gitrepo = GITRepo.new(repo)
      repos[gitrepo.id] = gitrepo
   }

   content = ""

   if path.size == 0
      template_params["repositories"] = Array.new
      repos.each_pair { |id, gitrepo|
         next unless gitrepo.valid

         repo = gitrepo.to_hash
         if gitrepo.commit
            repo["last_change"] = Time.now - gitrepo.commit.commit_time
            repo["last_change_str"] = age_string( Time.now - gitrepo.commit.commit_time )
         else
            repo["last_change"] = Time.now
            repo["last_change_str"] = "never"
         end

         template_params["repositories"] << repo
      }

      template_params["sort"] = cgi.has_key?("sort") ? cgi["sort"] : "id"
      template_params["sort"] = sort if not template_params["repositories"][0].has_key?(template_params["sort"])

      template_params["repositories"].sort! { |x, y| x[template_params["sort"]] <=> y[template_params["sort"]] }

      template_params["title"] = "gitarella - browse projects"
      content = Liquid::Template.parse( File.open("templates/projects.liquid").read ).render(template_params)
   elsif path.size == 1
      repo_id = path[0]; path.delete_at(0)
      unless repos.has_key?(repo_id)
         cgi.out({"status" => "NOT_FOUND"}) { "" }
         return
      end
      template_params["title"] = "gitarella - #{repo_id}"
      template_params["project_id"] = repo_id
      template_params["project_description"] = repos[repo_id].description
      template_params["commit_hash"] = repos[repo_id].sha1_head
      template_params["commit_desc"] = repos[repo_id].commit.description
      template_params["files_list"] = repos[repo_id].list
      template_params["repository"] = repos[repo_id].to_hash
      template_params["repository"]["last_change_date"] = Time.at(repos[repo_id].commit.commit_time).to_s
      template_params["heads"] = Array.new

      repos[repo_id].heads.each_pair { |name, head|
         template_params["heads"] << { "name" => name, "sha1" => head,
            "last_change_str" => age_string( Time.now - repos[repo_id].commit(head).commit_time )
            }
      }

      template_params["commits"] = Array.new

      commit = repos[repo_id].commit
      count = 0
      while commit and ( cgi["mode"] == "shortlog" or cgi["mode"] == "log" or ( cgi["mode"] == "summary" and count < 16 ) )
         ci = commit.to_hash
         ci["commit_date_age"] = age_string( Time.now - commit.commit_time )
         ci["author_date_str"] = Time.at(repos[repo_id].commit.author_time).to_s

         ci["short_description"] = str_reduce(ci["description"], 80)
         ci["description"].gsub!("\n", "<br />\n")

         template_params["commits"] << ci
         count = count+1
         commit = commit.parent_commit
      end

      template_params["more_commits"] = true if commit

      if not cgi.has_key?("mode") or cgi["mode"] == "tree"
         content = Liquid::Template.parse( File.open("templates/tree.liquid").read ).render(template_params)
      elsif cgi["mode"] == "summary"
         content = Liquid::Template.parse( File.open("templates/project-summary.liquid").read ).render(template_params)
      elsif cgi["mode"] == "shortlog"
         content = Liquid::Template.parse( File.open("templates/project-shortlog.liquid").read ).render(template_params)
      elsif cgi["mode"] == "log"
         content = Liquid::Template.parse( File.open("templates/project-log.liquid").read ).render(template_params)
      else
      end
   else
      repo_id = path[0]; path.delete_at(0)
      filepath = path.join('/')

      unless repos.has_key?(repo_id)
         cgi.header({"status" => CGI::NOT_FOUND})
         return
      end

      template_params["title"] = "gitarella - #{repo_id}"
      template_params["project_id"] = repo_id
      template_params["project_description"] = repos[repo_id].description
      template_params["commit_hash"] = repos[repo_id].sha1_head
      template_params["commit_desc"] = repos[repo_id].commit.description
      template_params["path"] = Array.new

      if repos[repo_id].list(filepath).empty?
         cgi.out({"status" => "NOT_FOUND"}) { "File not found" }
         return
      elsif repos[repo_id].list(filepath)[0]["type"] == "tree"
         prevelement = ""
         filepath.split("/").each { |element|
            template_params["path"] << { "path" => prevelement + "/" + element, "name" => element }
            prevelement = element
         }

         template_params["repopath"] = "/" + filepath
         template_params["files_list"] = repos[repo_id].list(filepath + "/")
         content = Liquid::Template.parse( File.open("templates/tree.liquid").read ).render(template_params)
      else
         prevelement = ""
         filepath.split("/").each { |element|
            template_params["path"] << { "path" => prevelement + "/" + element, "name" => element }
            prevelement = element
         }

         template_params["file"] = repos[repo_id].list(filepath)[0]
         template_params["file"]["data"] = repos[repo_id].file(filepath)
         if cgi["mode"] == "checkout" or template_params["file"]["data"] =~ /[^\x20-\x7e\s]{4,5}/
            staticmime = FileMagic.new(FileMagic::MAGIC_MIME).buffer(template_params["file"]["data"])

            cgi.out({ "content-type" => staticmime}) { template_params["file"]["data"] }
            return
         else
            template_params["file"]["lines"] = template_params["file"]["data"].split("\n")
            content = Liquid::Template.parse( File.open("templates/blob.liquid").read ).render(template_params)
         end
      end
   end

   cgi.out {
      Liquid::Template.parse( File.open("templates/main.liquid").read ).render(template_params.merge({ "content" => content }))
   }
end

# kate: encoding UTF-8; remove-trailing-space on; replace-trailing-space-save on; space-indent on; indent-width 3;