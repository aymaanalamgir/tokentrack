FROM ruby:3.4-slim AS development
WORKDIR /app
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libpq-dev libyaml-dev && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
EXPOSE 3001
ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3001"]

FROM development AS production
ENV RAILS_ENV=production
RUN mkdir -p log tmp/pids && chown -R 10001:10001 /app
USER 10001
