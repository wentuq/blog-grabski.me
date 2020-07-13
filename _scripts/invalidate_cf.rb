#!/usr/bin/env ruby

##
## usage: usage: AWS_SECRET_ACCESS_KEY=xxx AWS__ACCESS_KEY_ID=xxx CLOUDFRONT_DISTRIBUTION_ID=xxx ./invalidate_cf.rb "/file1.html" "/file2.html"
##

require 'aws-sdk'
require 'date'
require 'pry'

cf_dist_id = ENV['CLOUDFRONT_DISTRIBUTION_ID']

if [cf_dist_id].include?(nil)
  abort 'usage: AWS_SECRET_ACCESS_KEY=xxx AWS_ACCESS_KEY_ID=xxx CLOUDFRONT_DISTRIBUTION_ID=xxx ./invalidate_cf.rb "/file1.html" "/file2.html"'
end

files = ARGV

if files.count == 0
abort 'usage: AWS_SECRET_ACCESS_KEY=xxx AWS_ACCESS_KEY_ID=xxx CLOUDFRONT_DISTRIBUTION_ID=xxx ./invalidate_cf.rb "/file1.html" "/file2.html"'
end

puts "### Start invalidating Cloudfront cache ###"

client = Aws::CloudFront::Client.new(region: "us-east-1")

resp = client.create_invalidation({
:distribution_id    => cf_dist_id,
:invalidation_batch => {
  :paths => {
    :quantity => files.count,
    :items    => files
  },
  :caller_reference => "INVALIDATE_CF_" + DateTime.now.to_s
}
})

puts "invalidation status: #{resp.invalidation.status}"

### Commented lines
### waiting till status is Completed, unnecessary

# status = resp.invalidation.status

# while status == 'InProgress'
# resp = client.get_invalidation({
#       distribution_id: cf_dist_id,
#       id: resp.invalidation.id
# })

# status = resp.invalidation.status
# puts "status = #{ status }"
# sleep(rand(30))
# end

