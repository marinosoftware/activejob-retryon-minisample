class Objekt < ApplicationRecord
  def queue_job
    ObjektJob.perform_later(self)
  end
end
