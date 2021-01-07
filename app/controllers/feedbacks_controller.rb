# frozen_string_literal: true

class FeedbacksController < ApplicationController
  before_action :load_source

  def index
    # Need help to implement this part got some roadblocks
    # feedbacks = @feedback_source.feedbacks.includes(:review)
    # render json: FeedbackPresenter.present(feedback_data)
  end

  def create
    feedback_params = { feedback: {
      rating: params[:rating],
      review_attributes: { review: params[:review], tags: params[:tags] }
    } }
    if @feedback_source.feedbacks.create!(feedback_params[:feedback])
      render status: :created, json: { msg: "Success!" }
    else
      render json: feedback.errors.full_messages, status: :unprocessable_entity
    end
  end

  private
  # Need to change this logic(load_source) in the future to make it more reliable and dynamic
  def load_source
    source_type, id = request.path.split('/')[1, 2]
    @feedback_source = source_type.classify.constantize.find(id)
  end

  def permit_feedback_params
    params.require(:feedback).permit(:rating, :review, tags: [])
  end
end
