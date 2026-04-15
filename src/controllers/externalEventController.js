const { searchEvents } = require("../providers/ticketmasterService");

const getExternalEvents = async (req, res) => {
  try {
    const {
      keyword,
      city,
      countryCode,
      classificationName,
      startDateTime,
      endDateTime,
      size,
      page,
      sort
    } = req.query;

    const data = await searchEvents({
      keyword,
      city,
      countryCode,
      classificationName,
      startDateTime,
      endDateTime,
      size,
      page,
      sort
    });

    res.json({
      message: "External events fetched successfully",
      source: "ticketmaster",
      ...data
    });
  } catch (error) {
    res.status(500).json({
      message: "Failed to fetch external events",
      error: error.response?.data || error.message
    });
  }
};

module.exports = { getExternalEvents };