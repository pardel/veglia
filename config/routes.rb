Rails.application.routes.draw do
  root "dashboard#index"

  # Machine-readable current state, for anything that is not a browser.
  get "health", to: "dashboard#health"

  # Rails' own liveness endpoint: 200 if the app boots. Useful to curl
  # from another machine when deciding whether Veglia itself is the
  # thing that is down.
  get "up" => "rails/health#show", as: :rails_health_check
end
