class ProbesController < ApplicationController
  def write
    authorize!(:write)
    head :ok
  end
end
