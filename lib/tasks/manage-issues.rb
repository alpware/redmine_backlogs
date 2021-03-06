#!/usr/bin/env ruby

require 'rubygems'
require 'octokit'
require 'inifile'
require 'time'

class Issue
  def initialize(repo, issue)
    @repo = repo
    @issue = issue
    @labels = @issue.labels.collect{|l| l.name}

    @comments = @repo.client.issue_comments(@repo.repo, issue.number.to_s)

    @labels.delete_if{|l| l=~ /attention/ || l =~ /feedback/i || l =~ /^[0-9]+days?$/i }

    if (@labels & ['on-hold', 'feature-request', 'IMPORTANT-READ']).size == 0 # any of these labels means it doesn't participate in the workflow
      comment = {}
      @comments.each{|c|
        t = Time.parse(c.updated_at)
        if @repo.collaborators.include?(c.user.login)
          comment[:collab] = t
        else
          comment[:user] = t
        end
      }

      response = comment[:user] ? Integer((Time.now - comment[:user])) / (60 * 60 * 24) : nil

      if comment[:user] && (comment[:collab].nil? || comment[:user] > comment[:collab])
        @labels << 'attention'
      elsif comment[:user] && comment[:collab] && comment[:collab] > comment[:user] && response < 5
        @labels << 'feedback-required'
      elsif comment[:user] && comment[:collab] && comment[:collab] > comment[:user]
        @labels << 'no-feedback'
        @labels << "#{response}days"
      end
    end

    if @labels.size == 0
      @repo.client.remove_all_labels(@repo.repo, issue.number)
    else
      @repo.client.replace_all_labels(@repo.repo, issue.number, @labels)
    end

    @labels.each{|l| @repo.labels[l] = :keep}
  end
end

class Repository
  def initialize(repo, config)
    @repo = repo
    @client = Octokit::Client.new(config)
    @collaborators = @client.collaborators(@repo).collect{|u| u.login}
    @labels = {}
    @client.labels(@repo).each{|label| @labels[label] = :delete }

    begin
      page ||= 0
      page += 1
      issues = @client.list_issues(@repo, :page => page, :state => 'open')
      issues.each{|i| Issue.new(self, i) }
    end while issues.size != 0

    @labels.each_pair{|l, status|
      next if status == :keep
      next unless l =~ /days$/
      puts "delete label #{l}"
    }
  end

  attr_accessor :client, :repo, :collaborators, :labels
end

config = IniFile.load(File.expand_path('~/.gitconfig'))['github-issues']
config.keys.each{|k|
  sk = k.gsub(/[A-Z]/){|c| "_#{c.downcase}"}.intern
  config[sk] = config.delete(k)
}

Repository.new('backlogs/redmine_backlogs', config)
