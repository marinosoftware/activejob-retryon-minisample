class ObjektJob < ActiveJob::Base
  retry_on StandardError, attempts: 2

  def perform(objekt)
    objekt
  end
end
