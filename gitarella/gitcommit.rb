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

class GITCommit
   attr_accessor :author_name, :author_time, :commit_name, :commit_time, :tree,
      :sha1

   def initialize(repo, sha1)
      @repo = repo
      @sha1 = sha1
      repo.push_gitdir
      gitproc = IO.popen("git-rev-list --header --parents --max-count=1 #{@sha1}")
      data = gitproc.read.split("\n")
      gitproc.close

      $stderr.puts data.inspect

      verify_report = data[0].chomp; data.delete_at(0)
      @tree = data[0].split[1].chomp; data.delete_at(0)
      if data[0] =~ /^parent.*/
         @parent = data[0].split[1].chomp; data.delete_at(0)
         return nil unless verify_report == "#{@sha1} #{@parent}"
      else
         @parent = nil
         return nil unless verify_report == "#{@sha1}"
      end

      data[0] =~ /^author (.*) ([0-9]+) (\+[0-9]{4})$/
      @author_name = $1
      @author_time = Time.at($2.to_i)
      # author_tz = $3 # TODO Implement timezone diff

      data[1] =~ /^committer (.*) ([0-9]+) (\+[0-9]{4})$/
      @commit_name = $1
      @commit_time = Time.at($2.to_i)
      # committer_tz = $3 # TODO Implement timezone diff

      @description = data[3..data.size].join("\n")
   end

   def parent
      @repo.commit(@parent)
   end

   def commit_date_age
      age_string( Time.now - commit_time )
   end

   def commit_date_str
      Time.at(commit_time).to_s
   end

   def author_date_str
      Time.at(author_time).to_s
   end

   def short_description(size = 80)
      str_reduce(@description, size)
   end

   def description
      @description.gsub("\n", "<br />")
   end

   def changes(base = @parent)
      return $memcache["gitcommit-changes-#{sha1}_#{base}"] \
         if $memcache and $memcache["gitcommit-changes-#{sha1}_#{base}"]
      changes = Array.new

      @repo.push_gitdir
      gitproc = IO.popen("git-diff-tree -r #{base} #{sha1}")

      gitproc.each_line { |line|
         change = Hash.new

         line =~ /^:([0-7]{6}) ([0-7]{6}) ([0-9a-f]{40}) ([0-9a-f]{40}) ([A-Z]+)[ \t]*(.*)$/
         change["old_mode"] = $1
         change["new_mode"] = $2
         change["old_hash"] = $3
         change["new_hash"] = $4
         change["flags"] = $5
         change["file"] = $6

         changes << change
      }

      $stderr.puts changes.inspect

      gitproc.close
      $memcache["gitcommit-changes-#{sha1}_#{base}"] = changes if $memcache
      return changes
   end

   def to_hash
      return {
         "sha1" => @sha1, "tree" => @tree, "parent_sha1" => @parent,
         "author_name" => @author_name, "author_time" => @author_time,
         "author_date_str" => author_date_str,
         "commit_name" => @commit_name, "commit_time" => @commit_time,
         "commit_date_str" => commit_date_str, "commit_date_age" => commit_date_age,
         "description" => description, "short_description" => short_description
      }
   end
end

# kate: encoding UTF-8; remove-trailing-space on; replace-trailing-space-save on; space-indent on; indent-width 3;
