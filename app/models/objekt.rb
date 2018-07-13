class Objekt < ApplicationRecord
  def queue_no_retry_job
    ObjektNoRetryJob.perform_later(self)
  end

  def queue_retry_job
    ObjektRetryJob.perform_later(self)
  end

  def queue_standard_error_job
    ObjektStandardErrorJob.perform_later(self)
  end
end
