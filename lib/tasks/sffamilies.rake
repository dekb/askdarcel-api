# frozen_string_literal: true

namespace :sffamilies do
  desc('Associate resources to the sffamilies site based on service(s) with sffamilies category tag')
  task associate_resources: :environment do
    # Identify the sffamilites site
    sffamilies = Site.find_by(site_code: 'sffamilies')
    puts "Site Id: #{sffamilies.id}, Site Code: #{sffamilies.site_code}"

    Resource.transaction do
      # Find services that have the 'sffamilies' category name tag
      services = Service.joins(:categories).where(categories: { name: 'sffamilies' })
      services.each do |service|
        puts("Service id : #{service.id}, Service name: #{service.name}" \
        "from Resource id #{service.resource_id} has sffamilies category tag")

        # If the parent resource of the sffamilies service is not
        # connected to the site, append the site to it's list
        resource = Resource.find_by(id: service.id)
        unless resource.sites.include?(sffamilies)
          puts "Adding site association"
          new_sites = resource.sites.append(sffamilies)
          Resource.update(resource.id, sites: new_sites)
        end

        # Provide an updated list of the sites for the parent resource
        resource.sites.each do |resource_site|
          puts "#{resource_site.id}: #{resource_site.site_code}"
        end
      end
    end
  end
end
