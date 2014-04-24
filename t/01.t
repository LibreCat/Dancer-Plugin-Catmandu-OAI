#!/usr/bin/env perl

use strict;
use warnings;
use Test::More import => ['!pass'];

use Dancer;
use Dancer::Test;

use lib 't/lib';
use TestApp;

response_status_is [GET => '/oai'], 200, "response for GET /oai is 200";

response_status_is [POST => '/oai'], 200, "response for POST /oai is 200";

response_status_isnt [GET => '/oai'], 404, "response for GET /oai is not a 404";


done_testing 3;
