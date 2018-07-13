class ObjektStandardErrorJob < ActiveJob::Base
  retry_on StandardError, attempts: 2

  def perform(objekt)
    raise StandardError
  end
end

