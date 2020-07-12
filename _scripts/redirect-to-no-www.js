exports.handler = function(event, context, callback) {
  const request = event.Records[0].cf.request;
  const headers = request.headers;
  const host = headers.host[0].value;
  const url = 'https://grabski.me' + request.uri
  const response = {
      status: '301',
      statusDescription: 'Moved Permanently',
      headers: {
          location: [{
              key: 'Location',
              value: url,
          }],
      },
  };
  if (host == 'www.grabski.me' || host == 'd2irs6qpdg4tt2.cloudfront.net') {
      callback(null, response);
      return;
  }
  callback(null, request);
};