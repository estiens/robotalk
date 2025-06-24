class ModelsController < ApplicationController
  def index
    @models = RubyLLM::Models.all.sort_by(&:name)
  end
end
