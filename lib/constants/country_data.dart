/// Country and state/province data for checkout dropdowns.
/// Mirrors WooCommerce's supported countries and regions.
library country_data;

/// Countries with their ISO codes, names, and states.

/// Default countries list (ISO 3166-1 alpha-2 → country name).
const Map<String, String> countries = {
  'GB': 'United Kingdom (UK)',
  'US': 'United States (US)',
  'CA': 'Canada',
  'AU': 'Australia',
  'NG': 'Nigeria',
  'GH': 'Ghana',
  'KE': 'Kenya',
  'ZA': 'South Africa',
  'FR': 'France',
  'DE': 'Germany',
  'IT': 'Italy',
  'ES': 'Spain',
  'NL': 'Netherlands',
  'BE': 'Belgium',
  'PT': 'Portugal',
  'IE': 'Ireland',
  'BR': 'Brazil',
  'IN': 'India',
  'JP': 'Japan',
  'CN': 'China',
  'AE': 'United Arab Emirates',
  'SA': 'Saudi Arabia',
  'EG': 'Egypt',
};

/// Countries that use states/provinces (visible state dropdown).
const Set<String> countriesWithStates = {
  'US', 'CA', 'AU', 'BR', 'IN', 'CN', 'ES', 'DE', 'IT', 'JP', 'ZA',
};

/// States/provinces keyed by country ISO code.
const Map<String, Map<String, String>> states = {
  'US': {
    'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas',
    'CA': 'California', 'CO': 'Colorado', 'CT': 'Connecticut', 'DE': 'Delaware',
    'FL': 'Florida', 'GA': 'Georgia', 'HI': 'Hawaii', 'ID': 'Idaho',
    'IL': 'Illinois', 'IN': 'Indiana', 'IA': 'Iowa', 'KS': 'Kansas',
    'KY': 'Kentucky', 'LA': 'Louisiana', 'ME': 'Maine', 'MD': 'Maryland',
    'MA': 'Massachusetts', 'MI': 'Michigan', 'MN': 'Minnesota', 'MS': 'Mississippi',
    'MO': 'Missouri', 'MT': 'Montana', 'NE': 'Nebraska', 'NV': 'Nevada',
    'NH': 'New Hampshire', 'NJ': 'New Jersey', 'NM': 'New Mexico', 'NY': 'New York',
    'NC': 'North Carolina', 'ND': 'North Dakota', 'OH': 'Ohio', 'OK': 'Oklahoma',
    'OR': 'Oregon', 'PA': 'Pennsylvania', 'RI': 'Rhode Island', 'SC': 'South Carolina',
    'SD': 'South Dakota', 'TN': 'Tennessee', 'TX': 'Texas', 'UT': 'Utah',
    'VT': 'Vermont', 'VA': 'Virginia', 'WA': 'Washington', 'WV': 'West Virginia',
    'WI': 'Wisconsin', 'WY': 'Wyoming',
  },
  'CA': {
    'AB': 'Alberta', 'BC': 'British Columbia', 'MB': 'Manitoba',
    'NB': 'New Brunswick', 'NL': 'Newfoundland and Labrador', 'NT': 'Northwest Territories',
    'NS': 'Nova Scotia', 'NU': 'Nunavut', 'ON': 'Ontario', 'PE': 'Prince Edward Island',
    'QC': 'Quebec', 'SK': 'Saskatchewan', 'YT': 'Yukon',
  },
  'AU': {
    'ACT': 'Australian Capital Territory', 'NSW': 'New South Wales',
    'NT': 'Northern Territory', 'QLD': 'Queensland', 'SA': 'South Australia',
    'TAS': 'Tasmania', 'VIC': 'Victoria', 'WA': 'Western Australia',
  },
  'BR': {
    'AC': 'Acre', 'AL': 'Alagoas', 'AP': 'Amapá', 'AM': 'Amazonas',
    'BA': 'Bahia', 'CE': 'Ceará', 'DF': 'Distrito Federal', 'ES': 'Espírito Santo',
    'GO': 'Goiás', 'MA': 'Maranhão', 'MT': 'Mato Grosso', 'MS': 'Mato Grosso do Sul',
    'MG': 'Minas Gerais', 'PA': 'Pará', 'PB': 'Paraíba', 'PR': 'Paraná',
    'PE': 'Pernambuco', 'PI': 'Piauí', 'RJ': 'Rio de Janeiro', 'RN': 'Rio Grande do Norte',
    'RS': 'Rio Grande do Sul', 'RO': 'Rondônia', 'RR': 'Roraima', 'SC': 'Santa Catarina',
    'SP': 'São Paulo', 'SE': 'Sergipe', 'TO': 'Tocantins',
  },
  'ZA': {
    'EC': 'Eastern Cape', 'FS': 'Free State', 'GP': 'Gauteng', 'NL': 'KwaZulu-Natal',
    'LP': 'Limpopo', 'MP': 'Mpumalanga', 'NC': 'Northern Cape', 'NW': 'North West',
    'WC': 'Western Cape',
  },
};

/// Returns true if the given country uses a state/province field.
bool countryHasStates(String countryCode) => countriesWithStates.contains(countryCode.toUpperCase());

/// Returns state options for a country code, or empty map if none.
Map<String, String> getStatesForCountry(String countryCode) =>
    states[countryCode.toUpperCase()] ?? const {};
