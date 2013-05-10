module Sidekiq
  module Middleware
    module Client
      class UniqueJobs
        HASH_KEY_EXPIRATION = 30 * 60

        def call(worker_class, item, queue)
          enabled, expiration = worker_class.get_sidekiq_options['unique'],
            (worker_class.get_sidekiq_options['expiration'] || HASH_KEY_EXPIRATION)

          if enabled
            unique, payload = false, item.clone.slice(*%w(class queue args at))

            # Enabled unique scheduled
            if enabled == :all && payload.has_key?('at')
              expiration = (payload['at'].to_i - Time.now.to_i)
              payload.delete('at')
            end

            payload_hash = "locks:unique:#{Digest::MD5.hexdigest(Sidekiq.dump_json(payload))}"

            Sidekiq.redis do |conn|
              conn.watch(payload_hash)

              if conn.get(payload_hash)
                conn.unwatch
              else
                if expiration > 0
                  unique = conn.multi do
                    conn.setex(payload_hash, expiration, 1)
                  end
                else
                  conn.unwatch
                  unique = true
                end
              end
            end

            yield if unique
          else
            yield
          end
        end
      end
    end
  end
end
