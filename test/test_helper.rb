# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
require 'minitest/autorun'
require 'mocha/minitest'
require 'minitest/stub_any_instance'
require 'minitest/hooks/test'
require 'minitest/rg'

require 'bundler'
Bundler.require(:default, ENV.fetch('RACK_ENV', 'development'))

require './config/environment'

require './lib/types_for_dry'
require './lib/crossbeams_responses'
require './lib/base_repo'

root_dir = File.expand_path('../..', __FILE__)

Dir["#{root_dir}/helpers/**/*.rb"].each { |f| require f }
require './lib/base_service'
require './lib/base_interactor'
require './lib/ui_rules'

Dir["#{root_dir}/lib/applets/*.rb"].each { |f| require f }

class MiniTestWithHooks < Minitest::Test
  include Minitest::Hooks

  def around
    DB.transaction(rollback: :always, savepoint: true, auto_savepoint: true) do
      super
    end
  end

  def around_all
    DB.transaction(rollback: :always) do
      super
    end
  end
end

def current_user
  DevelopmentApp::User.new(
    id: 1,
    login_name: 'usr_login',
    user_name: 'User Name',
    password_hash: '$2a$10$wZQEHY77JEp93JgUUyVqgOkwhPb8bYZLswD5NVTWOKwU1ssQTYa.K',
    email: 'current_user@example.com',
    active: true
  )
end