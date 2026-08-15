# The pen and the two nets around it: what is waiting to be confirmed, who has
# written for the first time, and what the spam gate refused. An index and
# nothing else — resolving a hold is a nested resource of its own.
class SubscriptionsController < ApplicationController
  def index
    @subscriptions = Subscriptions.new
  end
end
