# Views and presenters

- Views render data. No calculations, queries, or complex conditionals.
- Display logic goes in a presenter. Build it in the controller, use it in the view.
- Helpers for simple formatting only, such as dates and currency. Past five lines, use a
  presenter.
- Extract repeated markup into partials. Partials take locals, never instance variables.
- App-wide partials go in `app/views/application/`.
- `render "orders/row"`, not `render partial: "orders/row"`.
- `link_to` for GET, `button_to` for every other verb.
- A view never references a model class. Pass the data in.
- Keep Stimulus controllers small. One behaviour each.
- No user-facing strings in the template. Everything goes through the locale files, keys sorted
  alphabetically, and a missing translation raises in development and test.

```erb
<%# Before %>
<% if order.line_items.sum(:amount) > order.buyer.credit_limit %>
  <p>Over limit by <%= number_to_currency(order.line_items.sum(:amount) - order.buyer.credit_limit) %></p>
<% end %>

<%# After — presenter built in the controller %>
<% if @order_presenter.over_limit? %>
  <p><%= t(".over_limit", amount: @order_presenter.excess) %></p>
<% end %>
```
