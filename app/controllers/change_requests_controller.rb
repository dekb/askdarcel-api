# frozen_string_literal: true
require_relative "../presenters/change_requests_presenter"

class ChangeRequestsController < ApplicationController
  def create
    ApplicationRecord.transaction do
      create_change_request
    end
  rescue ActiveRecord::UnknownAttributeError => e
    render status: :bad_request, json: unknown_attribute_error_json(e)
  rescue ActiveRecord::RecordInvalid => e
    render status: :bad_request, json: RecordInvalidPresenter.present(e)
  end

  def create_change_request
    if params[:resource_id]
      @change_request = ResourceChangeRequest.create(object_id: params[:resource_id], resource_id: params[:resource_id])
    elsif params[:service_id]
      @change_request = ServiceChangeRequest.create(object_id: params[:service_id], resource_id: Service.find(params[:service_id]).resource_id)
    elsif params[:address_id]
      if params[:change_request][:action]
        action_code = params[:change_request][:action] !~ /\D/ ? params[:change_request][:action].to_i : params[:change_request][:action]
        @change_request = AddressChangeRequest.create(action: action_code, object_id: params[:address_id], resource_id: Address.find(params[:address_id]).resource_id)
      else
        @change_request = AddressChangeRequest.create(object_id: params[:address_id], resource_id: Address.find(params[:address_id]).resource_id)
      end
    elsif params[:phone_id]
      resource_id = Phone.find(params[:phone_id]).resource_id
      @change_request = PhoneChangeRequest.create(object_id: params[:phone_id], resource_id: resource_id)
    elsif params[:schedule_day_id] || params[:type] == "schedule_days"
      schedule = nil
      if params[:schedule_day_id]
        schedule = Schedule.find(ScheduleDay.find(params[:schedule_day_id]).schedule_id)
      else
        schedule = Schedule.find(params[:schedule_id])
      end
      if (schedule.resource_id)
        @change_request = ScheduleDayChangeRequest.create(object_id: params[:schedule_day_id], resource_id: schedule.resource_id)
      else
        @change_request = ScheduleDayChangeRequest.create(object_id: params[:schedule_day_id], resource_id: Service.find(schedule.service_id).resource_id)
      end
    elsif params[:note_id]
      note = Note.find(params[:note_id])
      if (note.resource_id)
        @change_request = NoteChangeRequest.create(object_id: params[:note_id], resource_id: note.resource_id)
      else
        @change_request = NoteChangeRequest.create(object_id: params[:note_id], resource_id: Service.find(note.service_id).resource_id)
      end
    elsif params[:parent_resource_id] && params[:type]
      @change_request = handle_insert_change_request
    else
      render status: :bad_request
      return
    end

    @change_request.field_changes = field_changes

    persist_change (@change_request)

    render status: :created, json: ChangeRequestsPresenter.present(@change_request)
  end

  def geocode_address(address)
    begin
      return Geokit::Geocoders::GoogleGeocoder.geocode address.address_1 + "," + address.city + "," + address.state_province
    rescue => error
      puts "google geocoding failed for address " + address.id.to_s + ": " + error.message
    end
  end

  def handle_insert_change_request
    resource_id = params[:parent_resource_id]
    change_request = params[:change_request]
    case params[:type]
    when "addresses"
      puts "AddressInsertChangeRequest"
      address = Address.new
      permitted_fields = [
        :attention,
        :address_1,
        :address_2,
        :address_3,
        :address_4,
        :city,
        :state_province,
        :postal_code,
        :country,
        :online,
        :region,
        :name,
        :description,
        :transportation
      ]
      required_fields = [
        :address_1, 
        :city, 
        :state_province, 
        :postal_code, 
        :country
      ]
      change_request_params = change_request.require(:field_changes).permit(permitted_fields)
      change_request_params.require(required_fields)

      address.attributes = change_request_params
      address.resource_id = resource_id
      
      a = geocode_address address
      unless a.nil?
        address.latitude = a.latitude
        address.longitude = a.longitude
      end

      address.save!
      AddressChangeRequest.create(object_id: address.id, resource_id: Address.find(address.id).resource_id)
      
    when "phones"
      puts "PhoneInsertChangeRequest"
      phone = Phone.new
      permitted_fields = [
        :description,
        :number,
        :service_type,
        :service_id,
        :contact_id,
        :language_id
      ]
      required_fields = [:number, :service_type] 
      change_request_params = change_request.require(:field_changes).permit(permitted_fields)
      change_request_params.require(required_fields)
      phone.attributes = change_request_params
      phone.resource_id = resource_id

      phone.save!
      PhoneChangeRequest.create(object_id: phone.id, resource_id: Phone.find(phone.id).resource_id)
    else
      render status: :precondition_failed
    end
  end

  def index
    if !require_authorization!
      return
    end
    render json: ChangeRequestsWithResourcePresenter.present(changerequest.pending)
  end

  def approve
    if !require_authorization!
      return
    end
    change_request = ChangeRequest.find params[:change_request_id]
    if change_request.pending?
      change_request.field_changes = field_changes_approve change_request.id

      change_request.save!

      persist_change change_request
      change_request.approved!
      render status: :ok
    elsif change_request.approved?
      render status: :not_modified
    else
      render status: :precondition_failed
    end
  end

  def pending_count
    if !require_authorization!
      return
    end
    render json: {
             address_cr: ChangeRequest.all.where("type" => "AddressChangeRequest").where("status" => 0).count,
             note_cr: ChangeRequest.all.where("type" => "NoteChangeRequest").where("status" => 0).count,
             phone_cr: ChangeRequest.all.where("type" => "PhoneChangeRequest").where("status" => 0).count,
             resource_cr: ChangeRequest.all.where("type" => "ResourceChangeRequest").where("status" => 0).count,
             schedule_day_cr: ChangeRequest.all.where("type" => "ScheduleDayChangeRequest").where("status" => 0).count,
             service_cr: ChangeRequest.all.where("type" => "ServiceChangeRequest").where("status" => 0).count,
             new_resources: Resource.all.where("status" => 0).count,
             new_services: Service.all.where("status" => 0).count,
           }
  end

  def activity_by_timeframe
    if !require_authorization!
      return
    end
    start_date = params[:start_date].to_s
    end_date = params[:end_date].to_s
    render json: {
             new: {
               address_cr: ChangeRequest.all.where("type" => "AddressChangeRequest").where("DATE(created_at) > ?", start_date.to_datetime).where("DATE(created_at) < ?", end_date.to_datetime).count,
               note_cr: ChangeRequest.all.where("type" => "NoteChangeRequest").where("DATE(created_at) > ?", start_date.to_datetime).where("DATE(created_at) < ?", end_date.to_datetime).count,
               phone_cr: ChangeRequest.all.where("type" => "PhoneChangeRequest").where("DATE(created_at) > ?", start_date.to_datetime).where("DATE(created_at) < ?", end_date.to_datetime).count,
               resource_cr: ChangeRequest.all.where("type" => "ResourceChangeRequest").where("DATE(created_at) > ?", start_date.to_datetime).where("DATE(created_at) < ?", end_date.to_datetime).count,
               schedule_day_cr: ChangeRequest.all.where("type" => "ScheduleDayChangeRequest").where("DATE(created_at) > ?", start_date.to_datetime).where("DATE(created_at) < ?", end_date.to_datetime).count,
               service_cr: ChangeRequest.all.where("type" => "ServiceChangeRequest").where("DATE(created_at) > ?", start_date.to_datetime).where("DATE(created_at) < ?", end_date.to_datetime).count,
               new_resources: Resource.all.where("status" => 0).where("DATE(created_at) > ?", start_date.to_datetime).where("DATE(created_at) < ?", end_date.to_datetime).count,
               new_services: Service.all.where("status" => 0).where("DATE(created_at) > ?", start_date.to_datetime).where("DATE(created_at) < ?", end_date.to_datetime).count,
             },
             approved: {
               address_cr: ChangeRequest.all.where("type" => "AddressChangeRequest").where("DATE(updated_at) > ?", start_date.to_datetime).where("DATE(updated_at) < ?", end_date.to_datetime).where("status" => 1).count,
               note_cr: ChangeRequest.all.where("type" => "NoteChangeRequest").where("DATE(updated_at) > ?", start_date.to_datetime).where("DATE(updated_at) < ?", end_date.to_datetime).where("status" => 1).count,
               phone_cr: ChangeRequest.all.where("type" => "PhoneChangeRequest").where("DATE(updated_at) > ?", start_date.to_datetime).where("DATE(updated_at) < ?", end_date.to_datetime).where("status" => 1).count,
               resource_cr: ChangeRequest.all.where("type" => "ResourceChangeRequest").where("DATE(updated_at) > ?", start_date.to_datetime).where("DATE(updated_at) < ?", end_date.to_datetime).where("status" => 1).count,
               schedule_day_cr: ChangeRequest.all.where("type" => "ScheduleDayChangeRequest").where("DATE(updated_at) > ?", start_date.to_datetime).where("DATE(updated_at) < ?", end_date.to_datetime).where("status" => 1).count,
               service_cr: ChangeRequest.all.where("type" => "ServiceChangeRequest").where("DATE(updated_at) > ?", start_date.to_datetime).where("DATE(updated_at) < ?", end_date.to_datetime).where("status" => 1).count,
               new_resources: Resource.all.where("DATE(updated_at) > ?", start_date.to_datetime).where("DATE(updated_at) < ?", end_date.to_datetime).where("status" => 1).count,
               new_services: Service.all.where("DATE(updated_at) > ?", start_date.to_datetime).where("DATE(updated_at) < ?", end_date.to_datetime).where("status" => 1).count,
             },
           }
  end

  def replace_field_changes(change_request)
    return change_request
  end

  def reject
    if !require_authorization!
      return
    end
    change_request = ChangeRequest.find params[:change_request_id]
    if change_request.pending?
      change_request.rejected!
      render status: :ok
    elsif change_request.rejected?
      render status: :not_modified
    else
      render status: :precondition_failed
    end
  end

  private

  def persist_change(change_request)
    object_id = change_request.object_id
    puts object_id
    field_change_hash = get_field_change_hash change_request
    if change_request.is_a? ServiceChangeRequest
      puts "ServiceChangeRequest"
      service = Service.find(change_request.object_id)
      service.update field_change_hash
    elsif change_request.is_a? ResourceChangeRequest
      puts "ResourceChangeRequest"
      resource = Resource.find(change_request.object_id)
      resource.update field_change_hash
    elsif change_request.is_a? ScheduleDayChangeRequest
      puts "ScheduleDayChangeRequest"
      ScheduleDayChangeRequest.modify_schedule_day_hours(field_change_hash, params[:schedule_id], change_request.object_id)
    elsif change_request.is_a? NoteChangeRequest
      puts "NoteChangeRequest"
      note = Note.find(change_request.object_id)
      note.update field_change_hash
    elsif change_request.is_a? PhoneChangeRequest
      puts "PhoneChangeRequest"
      phone = Phone.find(change_request.object_id)
      if field_change_hash["number"]
        field_change_hash["number"] = Phonelib.parse(field_change_hash["number"], "US").full_e164
      end
      phone.update field_change_hash
    elsif change_request.is_a? AddressChangeRequest
      puts "AddressChangeRequest"
      address = Address.find(change_request.object_id)
      if change_request.remove?
        address.delete
      else
        a = geocode_address address
        unless a.nil?
          field_change_hash["latitude"] = a.latitude
          field_change_hash["longitude"] = a.longitude 
        end
        address.update field_change_hash
      end
    else
      puts "invalid request"
    end

    resource = change_request.resource
    return unless resource.present?

    # Touch 'updated_at' for resource. Signals to other systems that this
    # resource and/or its services have been modified.
    resource.touch

    if Rails.configuration.x.algolia.enabled
      # Update Algolia index for both the resource and all its services
      resource.index!
      resource.services.to_a.each &:index!
    end

    if Rails.configuration.x.airtable.api_key
      # Update AirTable with this resource's 'name', 'status' & 'updated_at'
      # Create new AirTable record if one wasn't there already
      update_in_airtable(resource)
    end
  end

  def get_field_change_hash(change_request)
    field_change_hash = {}
    change_request.field_changes.each do |field_change|
      puts field_change.field_name
      puts field_change.field_value
      # HACK: We need a better way to handle array values
      if field_change.field_name == "category_ids" || field_change.field_name == "eligibility_ids"
        value = JSON.parse(field_change.field_value)
      else
        value = field_change.field_value
      end

      field_change_hash[field_change.field_name] = value
    end
    field_change_hash
  end

  def field_changes
    if params[:change_request][:field_changes]
      fields = params[:change_request][:field_changes]
    else
      fields = params[:change_request]
    end
    fields.to_unsafe_h.map do |name, value|
      field_change_hash = {}
      # HACK: We need a better way to handle array values
      if name == "categories"
        field_change_hash[:field_name] = "category_ids"
        field_change_hash[:field_value] = value.map { |c| c[:id] }.to_json.to_s
      elsif name == "eligibilities"
        field_change_hash[:field_name] = "eligibility_ids"
        field_change_hash[:field_value] = value.map { |c| c[:id] }.to_json.to_s
      elsif name == "action"
        field_change_hash[:field_name] = name
        field_change_hash[:field_value] = @change_request.action
      else
        field_change_hash[:field_name] = name
        field_change_hash[:field_value] = value
      end
      field_change_hash[:change_request_id] = @change_request.id
      FieldChange.create(field_change_hash)
    end
  end

  def field_changes_approve(change_request_id)
    params[:change_request].to_unsafe_h.map do |fc|
      field_change_hash = {}
      field_change_hash[:field_name] = fc[0]
      field_change_hash[:field_value] = fc[1]
      field_change_hash[:change_request_id] = change_request_id
      FieldChange.create(field_change_hash)
    end
  end

  def changerequest
    ChangeRequest.includes(:field_changes, resource: [
                                             :addresses, :phones, :categories, :notes,
                                             schedule: :schedule_days,
                                             services: [:notes, :categories, { schedule: :schedule_days }],
                                             ratings: [:review],
                                           ])
  end

  # Given an ActiveRecord::UnknownAttributeError, returns a hash that would be
  # safe to return in a JSON API response.
  def unknown_attribute_error_json(error)
    { error: "Unknown attribute in request: \"#{error.attribute}\"" }
  end
end
