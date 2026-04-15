const axios = require("axios");

const BASE_URL = "https://app.ticketmaster.com/discovery/v2";

const mapEvent = (event) => {
  const firstImage = event.images?.[0]?.url || null;
  const venue = event._embedded?.venues?.[0];

  return {
    id: event.id,
    title: event.name || null,
    category: event.classifications?.[0]?.segment?.name || null,
    subcategory: event.classifications?.[0]?.genre?.name || null,
    location: venue?.city?.name || venue?.name || null,
    venue: venue?.name || null,
    country: venue?.country?.countryCode || null,
    event_date: event.dates?.start?.dateTime || event.dates?.start?.localDate || null,
    image: firstImage,
    source: "ticketmaster",
    url: event.url || null
  };
};

const searchEvents = async (params = {}) => {
  const response = await axios.get(`${BASE_URL}/events.json`, {
    params: {
      apikey: process.env.TICKETMASTER_API_KEY,
      keyword: params.keyword,
      city: params.city,
      countryCode: params.countryCode || "TR",
      classificationName: params.classificationName,
      startDateTime: params.startDateTime,
      endDateTime: params.endDateTime,
      size: params.size || 20,
      page: params.page || 0,
      sort: params.sort || "date,asc"
    }
  });

  const events = response.data?._embedded?.events || [];

  return {
    page: response.data.page || null,
    total: response.data.page?.totalElements || events.length,
    events: events.map(mapEvent)
  };
};

module.exports = { searchEvents };