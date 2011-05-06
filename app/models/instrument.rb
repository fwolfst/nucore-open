class Instrument < Product

  has_many :schedule_rules
  has_many :instrument_price_policies
  has_many :price_policies, :foreign_key => 'instrument_id'
  has_many :reservations
  has_many :instrument_statuses, :foreign_key => 'instrument_id'

  validates_presence_of :initial_order_status_id, :facility_account_id
  validates_numericality_of :account, :only_integer => true, :greater_than_or_equal_to => 0, :less_than_or_equal_to => 99999
  validates_numericality_of :min_reserve_mins, :max_reserve_mins, :only_integer => true, :greater_than_or_equal_to => 0, :allow_nil => true
  validates_uniqueness_of :relay_port, :scope => [:relay_ip]

  named_scope :relay_ip, :conditions => ["relay_ip IS NOT NULL"]

  def current_instrument_status
    instrument_statuses.find(:first, :order => 'created_at DESC')
  end
  
  def first_available_hour
    min = 23
    schedule_rules.each { |r|
      min = r.start_hour if r.start_hour < min
    }
    min
  end
  
  def last_available_hour
    max = 0
    schedule_rules.each { |r|
      hour = r.end_min == 0 ? r.end_hour - 1 : r.end_hour
      max  = hour if hour > max
    }
    max
  end

  # calculate the last possible reservation date based on all current price policies associated with this instrument
  def last_reserve_date
    today = Time.zone.now.to_date
    window = 0
    instrument_price_policies.current(self).each do |p|
      window = p.reservation_window if p.reservation_window > window
    end
    today + window.days
  end

  def last_reserve_days_from_now
    days = (last_reserve_date.to_time(:utc).beginning_of_day - Time.zone.now.utc.beginning_of_day) / (60 * 60 * 24) rescue 0
    days.to_i
  end

  # find the next available reservation based on schedule rules and existing reservations
  def next_available_reservation(after = Time.zone.now)
    reservation = nil
    day_of_week = after.wday
    0.upto(6) do |i|
      day_of_week = (day_of_week+i) % 6
      # find rules for day of week, sort by start hour
      rules = self.schedule_rules.select { |r| r.send("on_#{Date::ABBR_DAYNAMES[day_of_week].downcase}".to_sym) }.sort_by{ |r| r.start_hour }
      rules.each do |rule|
        # build rule start and end times
        tstart = Time.zone.local(after.year, after.month, after.day, rule.start_hour, rule.start_min, 0)
        tend   = Time.zone.local(after.year, after.month, after.day, rule.end_hour, rule.end_min, 0)
        # we can't start before tstart
        after  = tstart if after < tstart
        # check for conflicts with rule interval/duration time
        if (after.min % rule.duration_mins.to_i) != 0
          # adjust to next interval
          after += (rule.duration_mins.to_i - (after.min % rule.duration_mins.to_i)).minutes
        end
        while (after < tend)
          duration = self.min_reserve_mins.to_i < 15 ? 15.minutes : self.min_reserve_mins.to_i.minutes
          # build reservation
          reservation = self.reservations.new(:reserve_start_at => after, :reserve_end_at => after+duration)
          # check for conflicts with an existing reservation
          return reservation if reservation.valid?
          # we have a conflict, reset reservation and increment after by the rule's interval/duration time
          reservation = nil
          # after += self.min_reserve_mins.to_i.minutes
          after += duration
        end
      end
      # advance to start of next day
      after = after.end_of_day+1.second
    end
    reservation
  end

  def has_relay?
    (relay_ip && relay_port) ? true : false
  end

  def can_purchase? (group_ids = nil)
    return false if is_archived? || !facility.is_active?
    if schedule_rules.empty?
      false
    elsif group_ids.nil?
      current_price_policies.empty? || current_price_policies.any?{|pp| !pp.expired? && !pp.restrict_purchase?}
    elsif group_ids.empty?
      false
    else
      current_price_policies.empty? || current_price_policies.any?{|pp| !pp.expired? && !pp.restrict_purchase? && group_ids.include?(pp.price_group_id)}
    end
  end

  def is_approved_for? (user)
    return true if user.nil?
    if requires_approval?
      return requires_approval? && !product_users.find_by_user_id(user.id).nil?
    else
      true
    end
  end
end
