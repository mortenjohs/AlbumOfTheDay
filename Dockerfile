FROM ruby:3.0 as build-stage

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

RUN ["pwd"]

RUN ["ruby", "./generate_files.rb"]

FROM scratch AS export-stage
COPY --from=build-stage /usr/src/app/public/ /
