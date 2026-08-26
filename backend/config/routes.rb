Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[create destroy]
  resource :registrations, only: [:create]
  get '/me', to: 'me#show'

  resources :departments, only: [:index]
  resources :employees, only: %i[index show create update] do
    resources :salaries, only: %i[index create]
  end
  resources :salary_bands, only: %i[index create]
  post '/imports/employees', to: 'employee_imports#create'
  get '/currencies', to: 'currencies#index'
  get '/analytics/pay',           to: 'analytics#pay'
  get '/analytics/compa_ratio',   to: 'analytics#compa_ratio'
  get '/analytics/band_coverage', to: 'analytics#band_coverage'

  post '/probes/write', to: 'probes#write' if Rails.env.test?
end
