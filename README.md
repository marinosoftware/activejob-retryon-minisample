# README
This project provides an example of the issues with ActiveJob::Base.retry_on, and by extension, ActiveStorage::PurgeJob

### Basic Issue
If the target record of an ActiveJob is deleted before the job gets a chance to execute, `ActiveJob` will raise `ActiveRecord::RecordNotFound`.
If the ActiveJob has `retry_on StandardError`, the job will be re-queued.
Because the record was not found, the job is re-queued with nil as a parameter.
This results in `ActiveJob` throwing an `ArgumentError`, as the asterisk in this line turns `[]` into a `nil`:
`perform(*arguments)`

`ActiveStorage::PurgeJob` suffers from this problem.

I first came upon this issue when using Sidkiq, but the issue happens with all ActiveJob providers.

### Example
```rails console
irb(main):040:0> o = Objekt.create(name: Time.now.to_s)
irb(main):044:0> o.destroy
irb(main):045:0> o.queue_job
Enqueued ObjektJob (Job ID: 45e35f87-f43e-4ff7-b2a8-c1e73e5a5dab) to Async(default) with arguments: #<GlobalID:0x007fe19d3ada50 @uri=#<URI::GID gid://active-job-retry-on/Objekt/7>>
=> #<ObjektJob:0x007fe19d3ae860 @arguments=[#<Objekt id: 7, name: "2018-07-04 15:19:35 +0100", created_at: "2018-07-04 14:19:35", updated_at: "2018-07-04 14:19:35">], @job_id="45e35f87-f43e-4ff7-b2a8-c1e73e5a5dab", @queue_name="default", @priority=nil, @executions=0, @provider_job_id="cb7504ac-c582-48f2-adf4-b2807a6d7454">
  Objekt Load (0.3ms)  SELECT  "objekts".* FROM "objekts" WHERE "objekts"."id" = ? LIMIT ?  [["id", 7], ["LIMIT", 1]]
irb(main):046:0> Retrying ObjektJob in 3 seconds, due to a StandardError. The original exception was #<ActiveRecord::RecordNotFound: Couldn't find Objekt with 'id'=7>.
Enqueued ObjektJob (Job ID: 45e35f87-f43e-4ff7-b2a8-c1e73e5a5dab) to Async(default) at 2018-07-04 14:19:38 UTC
Performing ObjektJob (Job ID: 45e35f87-f43e-4ff7-b2a8-c1e73e5a5dab) from Async(default)
Error performing ObjektJob (Job ID: 45e35f87-f43e-4ff7-b2a8-c1e73e5a5dab) from Async(default) in 0.4ms: ArgumentError (wrong number of arguments (given 0, expected 1)):
[project]/app/jobs/objekt_job.rb:4:in `perform'
...
[ruby]/lib/ruby/gems/2.4.0/gems/concurrent-ruby-1.0.5/lib/concurrent/executor/ruby_thread_pool_executor.rb:319:in `block in create_worker'
Retrying ObjektJob in 3 seconds, due to a StandardError. The original exception was nil.
Enqueued ObjektJob (Job ID: 45e35f87-f43e-4ff7-b2a8-c1e73e5a5dab) to Async(default) at 2018-07-04 14:19:41 UTC
Performing ObjektJob (Job ID: 45e35f87-f43e-4ff7-b2a8-c1e73e5a5dab) from Async(default)
Error performing ObjektJob (Job ID: 45e35f87-f43e-4ff7-b2a8-c1e73e5a5dab) from Async(default) in 0.3ms: ArgumentError (wrong number of arguments (given 0, expected 1)):
[project]/app/jobs/objekt_job.rb:4:in `perform'
[ruby]/lib/ruby/gems/2.4.0/gems/activejob-5.2.0/lib/active_job/execution.rb:39:in `block in perform_now'
...
[ruby]/lib/ruby/gems/2.4.0/gems/concurrent-ruby-1.0.5/lib/concurrent/executor/ruby_thread_pool_executor.rb:319:in `block in create_worker'
Stopped retrying ObjektJob due to a StandardError, which reoccurred on 2 attempts. The original exception was nil.
```

### Workaround for ActiveStorage::PurgeJob
```
# config/initializers/active_storage_purge_job_monkey_patch.rb
# frozen_string_literal: true

# Provides asynchronous purging of ActiveStorage::Blob records via ActiveStorage::Blob#purge_later.
class ActiveStorage::PurgeJob < ActiveStorage::BaseJob
  # FIXME: Limit this to a custom ActiveStorage error
  retry_on StandardError

  def perform(blob=nil)
    blob.purge unless blob.nil?
  end
end
```

### Steps to reproduce

Delete an ActiveStorage::Blob immediately after calling #purge_later on it

### Expected behavior
ActiveRecord::RecordNotFound is raised, caught by ActiveStorage::PurgeJob.retry_on, and retried after a time.
On second attempt, the same thing happens.  This repeats until the max retries has been reached.

### Actual behavior
ActiveRecord::RecordNotFound is raised, caught by ActiveStorage::PurgeJob.retry_on, and retried after a time.
On second attempt, an ArgumentError is raised.  This repeats until the max retries has been reached.

### Whats happening

First attempt at running the job fails with ActiveRecord::RecordNotFound at the Deserialization stage
The job is incorrectly re-queued with no parameters, as a result of the failure in deserialization.
```
Enqueued ObjektJob (Job ID: f4dcffa1-5401-4dfd-a399-b5142643d449) to Async(default) with arguments: #<GlobalID:0x007ff088dbbde0 @uri=#<URI::GID gid://active-job-retry-on/Objekt/11>>
Retrying ObjektJob in 3 seconds, due to a StandardError. The original exception was #<ActiveRecord::RecordNotFound: Couldn't find Objekt with 'id'=11>.
Enqueued ObjektJob (Job ID: f4dcffa1-5401-4dfd-a399-b5142643d449) to Async(default) at 2018-07-11 13:12:03 UTC
```

Subsequent attempts at running the job fails because there serialized object is now nil
```
Performing ObjektJob (Job ID: f4dcffa1-5401-4dfd-a399-b5142643d449) from Async(default)
Error performing ObjektJob (Job ID: f4dcffa1-5401-4dfd-a399-b5142643d449) from Async(default) in 4.96ms: ArgumentError (wrong number of arguments (given 0, expected 1)):
Retrying ObjektJob in 3 seconds, due to a StandardError. The original exception was nil.
...
Stopped retrying ObjektJob due to a StandardError, which reoccurred on 2 attempts. The original exception was nil.
```

### System configuration
**Rails version**: 5.2.0
**Ruby version**: ruby 2.4.1p111 (2017-03-22 revision 58053) [x86_64-darwin16]

