class ObjektNoRetryJob < ActiveJob::Base
  def perform(objekt)
    objekt
  end
end
