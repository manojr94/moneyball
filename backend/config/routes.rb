Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[create destroy]
  get '/me', to: 'me#show'

  resources :employees, only: %i[index show create update]

  post '/probes/write', to: 'probes#write' if Rails.env.test?
end
