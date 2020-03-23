# frozen_string_literal: true

# Tasks that should be run once to alter data in production.

namespace :onetime do
  # Add new categories.
  #
  # This is idempotent so it is safe to run more than once
  task add_new_categories: :environment do
    Category.transaction do
      categories = [
        'Family Shelters',
        'Domestic Violence Shelters',
        'Advocacy & Legal Aid',
        'Eviction Defense',
        'Housing/Tenants Rights',
        'Youth',
        'Seniors',
        'End of Life Care',
        'Home Delivered Meals',
        'Senior Centers',
        'Congregate Meals',
        'Housing Rights',
        'Eviction Defense',
        'Domestic Violence',
        'Legal Representation',
        'Prison/Jail Related Services',
        'Legal Services',
        'Domestic Violence',
        'Domestic Violence Shelters',
        'Domestic Violence Hotlines',
        'Legal Representation',
        'Prison/Jail Related Services',
        'Re-entry Services',
        'Clean Slate',
        'Probation and Parole',
        'Legal Services'
      ]
      categories.each do |c|
        Category.find_or_create_by(name: c)
      end
    end
  end

  # A service should never point to the same schedule as a resource.
  # If it shares a schedule with its resource, it shouldn't have its own schedule row.
  desc 'Ensure services that inherit resource schedules do not have their own schedule'
  task fix_service_schedule_inheritance: :environment do
    Schedule.transaction do
      schedules = Schedule.joins(:service).joins('INNER JOIN resources ' \
          'ON resources.id = services.resource_id ' \
          'AND resources.id = schedules.resource_id')
      schedules.each do |s|
        puts format(
          'Service id %<service_id>i shares schedule %<schedule_id>i with Resource id %<resource_id>i',
          service_id: s.service_id,
          schedule_id: s.id,
          resource_id: s.resource_id
        )
        Schedule.create(resource_id: nil, service_id: s.service_id)
        Schedule.update(s.id, service_id: nil)
      end
      puts format('Updated %<num>i schedule records with nil service_id', num: schedules.length)
    end
  end

  # We can run this task in production for resources for HAP until we finish the frontend
  # to edit the hours_known flag.
  desc 'Mark certain resources with unknown hours'
  task mark_resource_hours_unknown: :environment do
    Resource.transaction do
      resource_names = [
        'The Q Foundation'
      ]
      Resource.where(name: resource_names).each do |r|
        Schedule.transaction do
          schedules = Schedule.where(resource_id: r.id)
          schedules.each do |s|
            puts format(
              'Marked id %<resource_id>i (%<resource_name>s) ' \
              'with schedule %<schedule_id>i as having unknown hours',
              resource_id: s.resource_id,
              resource_name: r.name,
              schedule_id: s.id
            )
            Schedule.update(s.id, hours_known: false)
          end
          puts format('Updated %<num>i schedule records with unknown hours', num: schedules.length)
        end
      end
    end
  end

  ############################################
  ## TASKS FOR HIERARCHICAL CATEGORIES WORK ##
  ############################################
  ## Steps
  ## 1. Remap resources/services under fewer categories
  #### e.g. remap resources/services under 'Prevent & Treat', 'Screening & Exams' to 'Checkup & Test',
  ## 2. Delete old category names that are now no longer used or mapped to any resource/service
  #### e.g. delete 'Prevent & Treat', 'Screening & Exams'
  ## 3. Rename categories to new names according to list provided
  #### e.g. rename 'Checkup & Test' => 'Medical Care'
  ## 4. Create new categories that were not renamed to in step 3
  ## 5. Add hierarchies between categories

  # STEP 1: Reassign categories in resources/services
  desc 'Reassign categories in resources and services to avoid non-unique error when renaming'
  task reassign_categories: :environment do
    reassignments = {
      'Prevent & Treat' => 'Medical Care',
      'Screening & Exams' => 'Medical Care',
      'Checkup & Test' => 'Medical Care',
      'Personal Hygiene' => 'Hygiene',
      'Support Network' => 'Counseling',
      'Supplies for School' => 'Books',
      'More Education' => 'Help Find School',
      'Job Placement' => 'Skills Assessment',
      'Help Find Work' => 'Skills Assessment',
      'End of Life Care' => 'End-of-Life Care',
      'Hospice' => 'End-of-Life Care',
      'Retirement Benefits' => 'Government Benefits',
      'Help Find Childcare' => 'Childcare',
      'Navigating the System' => 'Understand Government Programs',
      'Help Find Housing' => 'Housing Counseling',
      'Help Find School' => 'Education',
      'One-on-One Support' => 'Individual Counseling',
      'Skills & Training' => 'Job Training',
      'Vocational Training' => 'Job Training',
      'Home Delivered Meals' => 'Food Delivery',
      'Free Meals' => 'Food',
      'Help Pay for Food' => 'Food Benefits',
      'Help Escape Violence' => 'Immediate Safety',
      'Domestic Violence' => 'Immediate Safety',
      'Short-Term Housing' => 'Temporary Shelter',
      'Clothing Vouchers' => 'Clothing',
      'Home Goods' => 'Goods',
      'Legal Representation' => 'Representation',
      'Legal Services' => 'Legal',
      'Help Pay for Internet or Phone' => 'Help Pay for Utilities',
      'Money Management' => 'Financial Education',
      'Habitability' => 'Building Code Enforcement',
      'Clothes for School' => 'Clothing Vouchers',
      'Clothes for Work' => 'Clothing Vouchers',
      'Help Pay for Housing' => 'Housing Vouchers',
      'Rental Assistance' => 'Housing Vouchers',
      'Public Housing' => 'Subsidized Housing',
      'Eviction Prevention' => 'At Imminent Risk of Eviction',
      'Work' => 'Employment',
      'Money' => 'Financial Aid & Loans',
      'Help Pay for Transit' => 'Bus Passes'
    }
    reassignments.each do |old, new|
      old_category = Category.find_by(name: old)
      new_category = Category.find_by(name: new)
      ## Update categories for services
      #### find matching rows in categories_services and just update the category id
      CategoriesService.transaction do
        CategoriesService.where('category_id = ?', old_category.id).update_all(category_id: new_category.id)
      end
      ## Update categories for resources
      #### find matching resources containing old categories and update it by removing the old category and adding the new one
      Resource.transaction do
        matching_resources = Resource.joins(:categories).where("categories.name = ?", old_category.name)
        matching_resources.each do |r|
          new_categories = r.categories - r.categories.select { |c| c.name == old_category.name } \
           + [Category.find_by(name: new_category.name)]
          r.update(categories: new_categories)
        end
      end
    end
  end

  # STEP 2: Delete categories that were reassigned
  desc 'Delete categories in categories table that were reassigned'
  task delete_categories: :environment do
    Category.transaction do
      to_delete = [
        'Prevent & Treat',
        'Screening & Exams',
        'Checkup & Test',
        'Personal Hygiene',
        'Support Network',
        'Supplies for School',
        'More Education',
        'Job Placement',
        'Help Find Work',
        'End of Life Care',
        'Hospice',
        'Help Find Childcare',
        'Navigating the System',
        'Help Find Housing',
        'Help Find School',
        'One-on-One Support',
        'Skills & Training',
        'Vocational Training',
        'Home Delivered Meals',
        'Free Meals',
        'Help Pay for Food',
        'Help Escape Violence',
        'Domestic Violence',
        'Short-Term Housing',
        'Clothing Vouchers',
        'Home Goods',
        'Legal Representation',
        'Legal Services',
        'Help Pay for Internet or Phone',
        'Money Management',
        'Habitability',
        'Clothes for School',
        'Clothes for Work',
        'Help Pay for Housing',
        'Rental Assistance',
        'Public Housing',
        'Eviction Prevention',
        'Work',
        'Money',
        'Help Pay for Transit'
      ]
      to_delete.each do |c|
        Category.find_by(name: c).delete
      end
    end
  end

  # STEP 3: Rename categories to new names
  desc 'Rename certain categories to new names'
  task rename_categories: :environment do
    Category.transaction do
      renames = {
        'Transportation for Healthcare' => 'Healthcare Transportation',
        'Counseling' => 'Counseling & Support',
        'Help Pay for Childcare' => 'Childcare Financial Assistance',
        'Relief for Caregivers' => 'Caregiver Relief',
        'Help Fill out Forms' => 'Form & Paperwork Assistance',
        'Books' => 'School Supplies',
        'Financial Aid & Loans' => 'Finances & Benefits',
        'Help Pay for School' => 'Education Financial Assistance',
        'Transportation for School' => 'School Transportation',
        'Skills Assessment' => 'Job Placement & Skill Assessment',
        'Help Pay for Work Expenses' => 'Work Expenses',
        'Immediate Safety' => 'Physical Safety',
        'Help Pay for Utilities' => 'Utilities Financial Assistance',
        'Housing Vouchers' => 'Housing Financial Assistance',
        'Safe Housing' => 'Domestic Violence Shelter',
        'Bus Passes' => 'Transportation Financial Assistance',
        'Adoption' => 'Adoption & Foster Care',
        'At Imminent Risk of Eviction' => 'Eviction Prevention & Defense',
        'Disaster Assistance' => 'Disaster Response',
        'Early Childhood Education' => 'Early Childhood Care',
        'Case Management' => 'Case Manager',
        'Help Pay for Healthcare' => 'Healthcare Financial Assistance',
        'Homelessness Essentials' => 'Basic Needs',
        'Subsidized Housing' => 'Low-income Housing',
        'Employment' => 'Employment & Jobs'
      }
      renames.each do |old, new|
        Category.find_by(name: old).update(name: new)
      end
    end
  end

  # STEP 4: Create new categories that don't exist yet for the hierarchical categories work
  desc 'Add missing categories'
  task add_new_categories_hierarchical: :environment do
    Category.transaction do
      categories = [
        'Residential Care',
        'English as a Second Language',
        'Residential Treatment',
        'Criminal Justice Involvement',
        'Hot Meals',
        'Personal Safety Items',
        'Detox',
        'Computer or Internet Access',
        'Utilities & Insurance Assistance',
        'Transition Age Youth',
        'Medication Management',
        'Haircut',
        'Mental Health Medication',
        'Health',
        'Language',
        'ADA Transit',
        'Rec Teams',
        'Traumatic Brain Injury',
        'Loans',
        'Domestic Violence Hotline',
        'STD/STI Treatment & Prevention',
        'Animal Welfare',
        'Online Only',
        'Safety Education',
        'Drop-In Center',
        'Supported Employment',
        'Fitness & Exercise',
        'Medications',
        'Addiction Medicine',
        'Sexual & Reproductive Health',
        'Probation & Parole',
        'Disability',
        'Domestic Violence Counseling',
        'Online',
        'School Care'
      ]
      categories.each do |c|
        Category.find_or_create_by(name: c)
      end
    end
  end

  #STEP 5: Add hierarchies between categories
  desc 'Add category hierarchies into DB'
  task add_category_hierarchies: :environment do
    CategoryRelationship.transaction do
      # Hash structure
      # [
      #   1st tier => [
      #     2nd tier => [
      #       3rd tier => [
      #         4th tier,
      #         ...
      #       ],
      #       ...
      #     ],
      #     ...
      #   ],
      #   ... 
      # ]
      # Essentially, each category maps to an array of its children, recursively
      # except the last item in the ancestry (not necessarily 4th) which is a string
      hierarchies = {
        'Basic Needs' => {
          'Clothing' => nil,
          'Storage' => nil,
          'Waste Disposal' => nil,
          'Water' => nil,
          'Computer or Internet Access' => {
            'Wifi Access' => nil
          },
          'Food' => {
            'Congregate Meals' => nil,
            'Food Benefits' => nil,
            'Food Delivery' => nil,
            'Food Pantry' => nil,
            'Hot Meals' => nil,
            'Nutrition Education' => nil
          },
          'Goods' => {
            'Personal Safety Items' => nil
          },
          'Hygiene' => {
            'Hygiene Supplies' => nil,
            'Shower' => nil,
            'Toilet' => nil,
            'Haircut' => nil,
            'Dental Care' => nil
          }
        },
        'Care' => {
          'Animal Welfare' => nil,
          'Maternity Care' => nil,
          'Postnatal Care' => nil,
          'Physical Safety' => nil,
          'Guardianship' => nil,
          'In-Home Support' => nil,
          'Independent Living' => nil,
          'Senior Centers' => nil,
          'Adoption & Foster Care' => {
            'Transition Age Youth' => nil
          },
          'Counseling & Support' => {
            'Anger Management' => nil,
            'Bereavement' => nil,
            'Family Counseling' => nil,
            'Family Planning' => nil,
            'Group Therapy' => nil,
            'Home Visiting' => nil,
            'Individual Counseling' => nil,
            'Mentoring' => nil,
            'Peer Support' => nil,
            'Specialized Therapy' => nil,
            'Spiritual Support' => nil,
            'Substance Abuse Counseling' => nil,
            'Understand Disability' => nil,
            'Understand Government Programs' => nil,
            'Understand Mental Health' => nil,
            'Domestic Violence Counseling' => nil,
            'Case Manager' => {
              'Form & Paperwork Assistance' => nil
            },
            'Help Hotlines' => {
              'Domestic Violence Hotline' => nil
            },
            'Housing Counseling' => {
              'Eviction Prevention & Defense' => nil
            },
            'Support Groups' => {
              '12-Step' => nil,
              'Parenting Education' => nil
            },
            'Virtual Support' => {
              'Online' => nil
            }
          },
          'Daytime Care' => {
            'Adult Daycare' => nil,
            'Caregiver Relief' => nil,
            'Childcare' => {
              'School Care' => nil,
              'Childcare Financial Assistance' => nil,
              'Day Camp' => nil,
              'Early Childhood Care' => nil,
              'Preschool' => nil
            }
          },
          'End-of-Life Care' => {
            'Bereavement' => nil,
            'Pain Management' => nil,
            'Spiritual Support' => nil
          },
          'Recreation' => {
            'Fitness & Exercise' => nil,
            'Rec Teams' => nil
          },
          'Residential Care' => {
            'Assisted Living' => nil,
            'Nursing Home' => nil,
            'Residential Treatment' => nil
          }
        },
        'Disability' => {
          'ADA Transit' => nil,
          'Assisted Living' => nil,
          'Daily Life Skills' => nil,
          'Disability Screening' => nil,
          'Hearing Tests' => nil,
          'In-Home Support' => nil,
          'Independent Living' => nil,
          'Nursing Home' => nil,
          'Special Education' => nil,
          'Traumatic Brain Injury' => nil,
          'Understand Disability' => nil,
          'Vision Care' => nil,
          'Government Benefits' => {
            'Disability Benefits' => nil,
            'Food Benefits' => nil,
            'Retirement Benefits' => nil,
            'Understand Government Programs' => nil,
            'Unemployment Benefits' => nil
          }
        },
        'Education' => {
          'School Care' => nil,
          'Alternative Education' => nil,
          'Education Financial Assistance' => nil,
          'Financial Education' => nil,
          'Preschool' => nil,
          'School Supplies' => nil,
          'School Transportation' => nil,
          'Special Education' => nil,
          'Tutoring' => nil,
          'Understand Government Programs' => nil,
          'Health Education' => {
            'Daily Life Skills' => nil,
            'Family Planning' => nil,
            'Nutrition Education' => nil,
            'Parenting Education' => nil,
            'Safety Education' => nil,
            'Sex Education' => nil,
            'Understand Disability' => nil,
            'Understand Mental Health' => nil,
            'Disease Management' => {
              'HIV Treatment' => nil
            }
          },
          'Job Training' => {
            'Basic Literacy' => nil,
            'Computer Class' => nil,
            'GED/High-School Equivalency' => nil,
            'Interview Training' => nil,
            'Resume Development' => nil,
            'Specialized Training' => nil
          },
          'Language' => {
            'English as a Second Language' => nil,
            'Foreign Languages' => nil
          }
        },
        'Emergency' => {
          'Drop-In Center' => nil,
          'Eviction Prevention & Defense' => nil,
          'Physical Safety' => {
            'Disaster Response' => nil,
            'Domestic Violence Hotline' => nil,
            'Domestic Violence Shelters' => nil,
            'Personal Safety Items' => nil
          }
        },
        'Employment & Jobs' => {
          'Job Placement & Skill Assessment' => nil,
          'Supported Employment' => nil,
          'Work Expenses' => nil,
          'Workplace Rights' => nil,
          'Job Training' => {
            'Basic Literacy' => nil,
            'Computer Class' => nil,
            'GED/High-School Equivalency' => nil,
            'Interview Training' => nil,
            'Resume Development' => nil,
            'Specialized Training' => nil
          }
        },
        'Finances & Benefits' => {
          'Childcare Financial Assistance' => nil,
          'Education Financial Assistance' => nil,
          'Financial Education' => nil,
          'Loans' => nil,
          'Payee Services' => nil,
          'Tax Preparation' => nil,
          'Transportation Financial Assistance' => nil,
          'Work Expenses' => nil,
          'Government Benefits' => {
            'Disability Benefits' => nil,
            'Food Benefits' => nil,
            'Retirement Benefits' => nil,
            'Understand Government Programs' => nil,
            'Unemployment Benefits' => nil
          },
          'Healthcare Financial Assistance' => {
            'Disability Benefits' => nil,
            'Discounted Healthcare' => nil,
            'Health Insurance' => nil,
            'Prescription Assistance' => nil
          },
          'Housing Financial Assistance' => {
            'Utilities Financial Assistance' => nil,
            'Home & Renters Insurance' => nil
          },
          'Insurance' => {
            'Health Insurance' => nil,
            'Home & Renters Insurance' => nil
          }
        },
        'Health' => {
          'Dental Care' => nil,
          'Drop-In Center' => nil,
          'Healthcare Transportation' => nil,
          'Health Insurance' => nil,
          'Hearing Tests' => nil,
          'Medical Supplies' => nil,
          'Traumatic Brain Injury' => nil,
          'Vision Care' => nil,
          'Addiction & Recovery' => {
            '12-Step' => nil,
            'Detox' => nil,
            'Drug Testing' => nil,
            'Addiction Medicine' => nil,
            'Residential Treatment' => nil,
            'Sober Living' => nil,
            'Substance Abuse Counseling' => nil
          },
          'End-of-Life Care' => {
            'Bereavement' => nil,
            'Pain Management' => nil
          },
          'Healthcare Financial Assistance' => {
            'Discounted Healthcare' => nil,
            'Health Insurance' => nil,
            'Prescription Assistance' => nil
          },
          'Health Education' => {
            'Daily Life Skills' => nil,
            'Family Planning' => nil,
            'Nutrition Education' => nil,
            'Parenting Education' => nil,
            'Safety Education' => nil,
            'Sex Education' => nil,
            'Understand Disability' => nil,
            'Understand Mental Health' => nil,
            'Disease Management' => {
              'HIV Treatment' => nil
            }
          },
          'Medical Care' => {
            'Disability Screening' => nil,
            'Disease Screening' => nil,
            'Early Childhood Care' => nil,
            'In-Home Support' => nil,
            'Nursing Home' => nil,
            'Pain Management' => nil,
            'Physical Therapy' => nil,
            'Primary Care' => nil,
            'Residential Treatment' => nil,
            'Specialized Therapy' => nil,
            'Vaccinations' => nil,
            'Disease Management' => {
              'HIV Treatment' => nil
            }
          },
          'Medications' => {
            'Addiction Medicine' => nil,
            'Medication Management' => nil,
            'Mental Health Medication' => nil,
            'Prescription Assistance' => nil
          },
          'Mental Health Care' => {
            'Anger Management' => nil,
            'Family Counseling' => nil,
            'Group Therapy' => nil,
            'Guardianship' => nil,
            'Hoarding' => nil,
            'Individual Counseling' => nil,
            'Mental Health Evaluation' => nil,
            'Mental Health Medication' => nil,
            'Psychiatric Emergency Services' => nil,
            'Residential Treatment' => nil,
            'Substance Abuse Counseling' => nil,
            'Understand Mental Health' => nil
          },
          'Sexual & Reproductive Health' => {
            'Birth Control' => nil,
            'Family Planning' => nil,
            'Fertility' => nil,
            'Maternity Care' => nil,
            'Pregnancy Tests' => nil,
            'Postnatal Care' => nil,
            'Sex Education' => nil,
            'STD/STI Treatment & Prevention' => {
              'HIV Treatment' => nil
            }
          },
        },
        'Housing' => {
          'Independent Living' => nil,
          'Sober Living' => nil,
          'Transition Age Youth' => nil,
          'Housing Counseling' => {
            'Eviction Prevention & Defense' => nil
          },
          'Housing Financial Assistance' => {
            'Utilities & Insurance Assistance' => nil
          },
          'Long-Term Housing' => {
            'Low-income Housing' => nil
          },
          'Residential Care' => {
            'Assisted Living' => nil,
            'Nursing Home' => nil,
            'Residential Treatment' => nil
          },
          'Temporary Shelter' => {
            'Domestic Violence Shelter' => nil,
            'Family Shelters' => nil
          },
        },
        'Legal' => {
          'Identification Recovery' => nil,
          'Mediation' => nil,
          'Notary' => nil,
          'Representation' => nil,
          'Advocacy & Legal Aid' => {
            'Adoption & Foster Care' => nil,
            'Building Code Enforcement' => nil,
            'Discrimination & Civil Rights' => nil,
            'Guardianship' => nil,
            'Workplace Rights' => nil
          },
          'Citizenship & Immigration' => {
            'English as a Second Language' => nil
          },
          'Criminal Justice Involvement' => {
            'Clean Slate' => nil,
            'Prison/Jail Related Services' => nil,
            'Probation & Parole' => nil,
            'Re-entry Services' => nil
          },
          'Housing Counseling' => {
            'Eviction Prevention & Defense' => nil
          },
          'Translation & Interpretation' => {
            'English as a Second Language' => nil
          }
        },
        'LGBTQ' => nil,
        'MOHCD Funded' => nil,
        'Technology' => {
          'Computer Class' => nil,
          'Smartphones' => nil,
          'Computer or Internet Access' => {
            'Wifi Access' => nil
          },
          'Virtual Support' => {
            'Online' => nil
          }
        },
        'Transit' => {
          'ADA Transit' => nil,
          'Healthcare Transportation' => nil,
          'School Transportation' => nil,
          'Transportation Financial Assistance' => nil
        }
      }
      hierarchies.each do |first_tier_category, firsts_children|
        process_tier(first_tier_category, firsts_children)
      end
    end
  end

  def process_tier(category, next_tier)
    cat_obj = Category.find_by(name: category)
    if cat_obj == nil
      ## this shouldn't happen; data above is already vetted to exist in db
      puts "Category " + category + " does not exist"
      return
    end
    if next_tier != nil
      next_tier.each do |child_category, next_next_tier|
        # this also shouldn't happen
        child_cat_obj = Category.find_by(name: child_category)
        next if child_cat_obj == nil

        # put parent child relationship between category and child_category
        CategoryRelationship.find_or_create_by({:parent_id => cat_obj["id"], :child_id => child_cat_obj["id"]})
        # then process child
        process_tier(child_category, next_next_tier)
      end
    end
  end
end
