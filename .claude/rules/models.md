# Models and domain objects

## Where domain logic lives

- No service objects. Domain classes live in `app/models/`, namespaced, never `app/services/`.
- Name classes after domain nouns, not actions. No `*Service`, `*Manager`, `*Handler`.
- Domain verbs instead of `.call` or `.perform`: `#submit`, `#complete`, `#deliver`, `#save`.
- `ActiveModel::Model` for POROs that need validation or form integration.
- When a model gets large, look for a domain model to extract rather than adding a mixin.
- Avoid case statements on type and mixin abuse.

```ruby
# Before — app/services/order_approval_service.rb
class OrderApprovalService
  def self.call(order, approver)
    order.update(approved_at: Time.current, approver: approver)
    ApprovalMailer.approved(order).deliver_later
  end
end

# After — app/models/order/approval.rb
class Order::Approval
  include ActiveModel::Model

  attr_accessor :order, :approver

  validates :approver, presence: true

  def submit
    return false unless valid?

    order.update!(approved_at: Time.current, approver: approver)
    ApprovalMailer.approved(order).deliver_later
    true
  end
end
```

## ActiveRecord

- Order the file: constants, macros, public methods, private methods.
- Associations above validations. Associations sorted by type then name; validations sorted by
  attribute.
- `def self.settled` rather than `scope :settled`. Either way it stays a one-liner — anything
  longer belongs in a query object.
- `validates :name, presence: true` style, with all validations for one column together.
- When validating an association, target the object (`:user`), not the column (`:user_id`).
  `belongs_to` is required by default, so an extra presence validation is usually redundant.
- `touch: true` on `belongs_to`.
- Never bypass validations: no `save(validate: false)`, `update_attribute`, or `toggle`.
- Don't name a method after a column in the same class.
- SQL strings stay inside models. No `where("supplier_id IS NOT NULL")` in a controller, view,
  or job.

## Callbacks

- Callbacks are for data integrity only: normalising a field, setting a default.
- Never send email, charge a card, or call an external service from a callback. Put it in the
  object that owns the action.
- Raise to stop a callback. Returning `false` does nothing.
