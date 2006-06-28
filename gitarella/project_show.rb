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
# along with gitarella; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

module Gitarella
class GitarellaCGI
   def project_show
      get_repo_id

      mode = @cgi.has_key?("mode") ? @cgi["mode"] : "tree"
      case mode
         when "summary"
            get_commits(15)
            @content = parse_template("project-summary")

         when "shortlog", "log"
            get_commits(30, @commit_hash)
            @content = parse_template("project-" + mode)

         when "commit"
            @template_params["commit"] = @repo.commit(@commit_hash).to_hash
            @template_params["commit"]["changes"] = @repo.commit(@commit_hash).changes
            @content = parse_template("project-commit")

         when "tag"
            @template_params["tag"] = GITTag.get(@repo, @cgi["htag"]).to_hash
            @content = parse_template("project-tag")

         else # fallback
            @content = parse_template("tree")
      end
   end

   def get_commits(number = 10, from = @commit_hash)
      @template_params["commits"] = Array.new

      commit = @@repos[@repo_id].commit(from)
      count = 0
      while commit and count < number
         @template_params["commits"] << commit.to_hash

         commit = commit.parent
         count = count+1
      end

      @template_params["prev_commits"] = ( from != @@repos[@repo_id].head ) ? @@repos[@repo_id].commit(from).sha1 : false
      @template_params["more_commits"] = commit ? commit.sha1 : false
   end
end
end

# kate: encoding UTF-8; remove-trailing-space on; replace-trailing-space-save on; space-indent on; indent-width 3;
