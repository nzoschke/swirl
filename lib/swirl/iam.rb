require 'swirl/helpers'

module Swirl
  class EntityAlreadyExists < StandardError ; end

  class IAM < Base
    include Helpers::Compactor
    include Helpers::Expander

    def initialize(options)
      super
      @version = "2010-05-08"
      @url = URI(options[:url] || "https://iam.amazonaws.com")
    end

  end
end