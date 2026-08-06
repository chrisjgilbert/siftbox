# Controllers and routes

- Controllers handle HTTP only: read the request, hand off to a model, return a response.
- No business logic, calculations, email sending, or multi-object work in a controller.
- One instance variable per action. Two means either a missing object or a missing route.
- A long action is business logic in the wrong place. Move it to a model or PORO.
- Order the file: filters, public methods, private methods. `private`, not `protected`.
- Strong params in a private method. Never `params.permit!`.
- Failed form renders return `status: :unprocessable_entity`. Turbo ignores the response
  otherwise.

## Routes

- Resourceful routes only. A custom verb action is a missing noun.
- List what's exposed with `only:`. Never `except:`.
- Avoid `member` and `collection` blocks — a nested resource is usually the answer.
- Sort resources alphabetically.
- `_path` helpers everywhere except mailer views and redirects, which take `_url`.

```ruby
# Before
resources :orders do
  member { post :approve }
end

def approve
  @order = Order.find(params[:id])
  @order.update(approved_at: Time.current)
  OrderMailer.approved(@order).deliver_later
  redirect_to @order
end

# After
resources :orders, only: [:index, :show] do
  resource :approval, only: :create
end

# app/controllers/orders/approvals_controller.rb
def create
  approval = Order::Approval.new(order: order, approver: current_user)

  if approval.submit
    redirect_to approval.order
  else
    render "orders/show", status: :unprocessable_entity
  end
end
```
