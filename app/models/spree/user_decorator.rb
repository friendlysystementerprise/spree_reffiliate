Spree::User.class_eval do
  include Spree::TransactionRegistrable
  attr_accessor :referral_code, :affiliate_code, :can_activate_associated_partner

  has_one :referral
  has_one :referred_record
  has_one :affiliate, through: :referred_record, foreign_key: :affiliate_id
  has_one :affiliate_record, class_name: 'Spree::ReferredRecord'
  has_many :transactions, as: :commissionable, class_name: 'Spree::CommissionTransaction', dependent: :restrict_with_error

  after_create :create_referral
  after_create :process_referral
  after_create :process_affiliate
  after_update :activate_associated_partner, if: :associated_partner_activable?

  validates :referral_credits, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def referred_by
    referred_record.try(:referral).try(:user)
  end

  def referred_count
    referral.referred_records.count
  end

  def referred?
    !referred_record.try(:referral).try(:user).nil?
  end

  def affiliate?
    !affiliate.nil?
  end

  def associated_partner
    @associated_partner ||= Spree::Affiliate.find_by(email: email)
  end

  def associated_partner?
    !associated_partner.nil?
  end

  protected
    def password_required?
      if new_record? && spree_roles.include?(Spree::Role.affiliate)
        false
      else
        super
      end
    end

  private
    def process_referral
      if referral_code.present?
        referred = Spree::Referral.where('lower(code) = ?', referral_code.downcase).first
        if referred
          referred.referred_records.create(user: self)
          point_entry = create_points_entry(referred.user) if referrer_eligible?(referred.user)
        end
      end
    end

    def process_affiliate
      if affiliate_code.present?
        affiliated = Spree::Affiliate.where('lower(path) = ?', affiliate_code.downcase).first
        if affiliated
          register_commission_transaction(affiliated)
          affiliated.referred_records.create(user: self)
        end
      end
    end

    def activate_associated_partner
      associated_partner.update_attributes(activation_token: nil, activated_at: Time.current, active: true)
    end

    def associated_partner_activable?
      can_activate_associated_partner && associated_partner? && !associated_partner.active?
    end

    def create_store_credits(referrer)
      referrer.loyalty_points_balance += 50
    end

    def create_points_entry(referrer)
      item = Spree::LoyaltyPointsTransaction.new(loyalty_points: 50, comment: "Referral", user_id: referrer.id, type: 'Spree::LoyaltyPointsCreditTransaction')
      item.save!
    end

    def referral_amount(referrer)
      referrer.referral_credits || Spree::Config[:referral_credits]
    end

    def referrer_eligible?(user)
      Spree::Config[:referrer_benefit_enabled] && user.referrer_benefit_enabled
    end

    def referral_store_credit_category
      @store_credit_category ||= Spree::StoreCreditCategory.find_or_create_by(name: Spree::StoreCredit::REFERRAL_STORE_CREDIT_CATEGORY)
    end
end
