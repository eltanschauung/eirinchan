defmodule Eirinchan.CountryCodes do
  @moduledoc """
  Resolves ISO 3166-1 country names and alpha-3 identifiers to alpha-2 flag codes.
  """

  @country_data """
  ad|and|Andorra||Principality of Andorra
  ae|are|United Arab Emirates||
  af|afg|Afghanistan||Islamic Republic of Afghanistan
  ag|atg|Antigua and Barbuda||
  ai|aia|Anguilla||
  al|alb|Albania||Republic of Albania
  am|arm|Armenia||Republic of Armenia
  ao|ago|Angola||Republic of Angola
  aq|ata|Antarctica||
  ar|arg|Argentina||Argentine Republic
  as|asm|American Samoa||
  at|aut|Austria||Republic of Austria
  au|aus|Australia||
  aw|abw|Aruba||
  ax|ala|Åland Islands||
  az|aze|Azerbaijan||Republic of Azerbaijan
  ba|bih|Bosnia and Herzegovina||Republic of Bosnia and Herzegovina
  bb|brb|Barbados||
  bd|bgd|Bangladesh||People's Republic of Bangladesh
  be|bel|Belgium||Kingdom of Belgium
  bf|bfa|Burkina Faso||
  bg|bgr|Bulgaria||Republic of Bulgaria
  bh|bhr|Bahrain||Kingdom of Bahrain
  bi|bdi|Burundi||Republic of Burundi
  bj|ben|Benin||Republic of Benin
  bl|blm|Saint Barthélemy||
  bm|bmu|Bermuda||
  bn|brn|Brunei Darussalam||
  bo|bol|Bolivia, Plurinational State of|Bolivia|Plurinational State of Bolivia
  bq|bes|Bonaire, Sint Eustatius and Saba||Bonaire, Sint Eustatius and Saba
  br|bra|Brazil||Federative Republic of Brazil
  bs|bhs|Bahamas||Commonwealth of the Bahamas
  bt|btn|Bhutan||Kingdom of Bhutan
  bv|bvt|Bouvet Island||
  bw|bwa|Botswana||Republic of Botswana
  by|blr|Belarus||Republic of Belarus
  bz|blz|Belize||
  ca|can|Canada||
  cc|cck|Cocos (Keeling) Islands||
  cd|cod|Congo, The Democratic Republic of the||
  cf|caf|Central African Republic||
  cg|cog|Congo||Republic of the Congo
  ch|che|Switzerland||Swiss Confederation
  ci|civ|Côte d'Ivoire||Republic of Côte d'Ivoire
  ck|cok|Cook Islands||
  cl|chl|Chile||Republic of Chile
  cm|cmr|Cameroon||Republic of Cameroon
  cn|chn|China||People's Republic of China
  co|col|Colombia||Republic of Colombia
  cr|cri|Costa Rica||Republic of Costa Rica
  cu|cub|Cuba||Republic of Cuba
  cv|cpv|Cabo Verde||Republic of Cabo Verde
  cw|cuw|Curaçao||Curaçao
  cx|cxr|Christmas Island||
  cy|cyp|Cyprus||Republic of Cyprus
  cz|cze|Czechia||Czech Republic
  de|deu|Germany||Federal Republic of Germany
  dj|dji|Djibouti||Republic of Djibouti
  dk|dnk|Denmark||Kingdom of Denmark
  dm|dma|Dominica||Commonwealth of Dominica
  do|dom|Dominican Republic||
  dz|dza|Algeria||People's Democratic Republic of Algeria
  ec|ecu|Ecuador||Republic of Ecuador
  ee|est|Estonia||Republic of Estonia
  eg|egy|Egypt||Arab Republic of Egypt
  eh|esh|Western Sahara||
  er|eri|Eritrea||the State of Eritrea
  es|esp|Spain||Kingdom of Spain
  et|eth|Ethiopia||Federal Democratic Republic of Ethiopia
  fi|fin|Finland||Republic of Finland
  fj|fji|Fiji||Republic of Fiji
  fk|flk|Falkland Islands (Malvinas)||
  fm|fsm|Micronesia, Federated States of||Federated States of Micronesia
  fo|fro|Faroe Islands||
  fr|fra|France||French Republic
  ga|gab|Gabon||Gabonese Republic
  gb|gbr|United Kingdom||United Kingdom of Great Britain and Northern Ireland
  gd|grd|Grenada||
  ge|geo|Georgia||
  gf|guf|French Guiana||
  gg|ggy|Guernsey||
  gh|gha|Ghana||Republic of Ghana
  gi|gib|Gibraltar||
  gl|grl|Greenland||
  gm|gmb|Gambia||Republic of the Gambia
  gn|gin|Guinea||Republic of Guinea
  gp|glp|Guadeloupe||
  gq|gnq|Equatorial Guinea||Republic of Equatorial Guinea
  gr|grc|Greece||Hellenic Republic
  gs|sgs|South Georgia and the South Sandwich Islands||
  gt|gtm|Guatemala||Republic of Guatemala
  gu|gum|Guam||
  gw|gnb|Guinea-Bissau||Republic of Guinea-Bissau
  gy|guy|Guyana||Republic of Guyana
  hk|hkg|Hong Kong||Hong Kong Special Administrative Region of China
  hm|hmd|Heard Island and McDonald Islands||
  hn|hnd|Honduras||Republic of Honduras
  hr|hrv|Croatia||Republic of Croatia
  ht|hti|Haiti||Republic of Haiti
  hu|hun|Hungary||Hungary
  id|idn|Indonesia||Republic of Indonesia
  ie|irl|Ireland||
  il|isr|Israel||State of Israel
  im|imn|Isle of Man||
  in|ind|India||Republic of India
  io|iot|British Indian Ocean Territory||
  iq|irq|Iraq||Republic of Iraq
  ir|irn|Iran, Islamic Republic of|Iran|Islamic Republic of Iran
  is|isl|Iceland||Republic of Iceland
  it|ita|Italy||Italian Republic
  je|jey|Jersey||
  jm|jam|Jamaica||
  jo|jor|Jordan||Hashemite Kingdom of Jordan
  jp|jpn|Japan||
  ke|ken|Kenya||Republic of Kenya
  kg|kgz|Kyrgyzstan||Kyrgyz Republic
  kh|khm|Cambodia||Kingdom of Cambodia
  ki|kir|Kiribati||Republic of Kiribati
  km|com|Comoros||Union of the Comoros
  kn|kna|Saint Kitts and Nevis||
  kp|prk|Korea, Democratic People's Republic of|North Korea|Democratic People's Republic of Korea
  kr|kor|Korea, Republic of|South Korea|
  kw|kwt|Kuwait||State of Kuwait
  ky|cym|Cayman Islands||
  kz|kaz|Kazakhstan||Republic of Kazakhstan
  la|lao|Lao People's Democratic Republic|Laos|
  lb|lbn|Lebanon||Lebanese Republic
  lc|lca|Saint Lucia||
  li|lie|Liechtenstein||Principality of Liechtenstein
  lk|lka|Sri Lanka||Democratic Socialist Republic of Sri Lanka
  lr|lbr|Liberia||Republic of Liberia
  ls|lso|Lesotho||Kingdom of Lesotho
  lt|ltu|Lithuania||Republic of Lithuania
  lu|lux|Luxembourg||Grand Duchy of Luxembourg
  lv|lva|Latvia||Republic of Latvia
  ly|lby|Libya||Libya
  ma|mar|Morocco||Kingdom of Morocco
  mc|mco|Monaco||Principality of Monaco
  md|mda|Moldova, Republic of|Moldova|Republic of Moldova
  me|mne|Montenegro||Montenegro
  mf|maf|Saint Martin (French part)||
  mg|mdg|Madagascar||Republic of Madagascar
  mh|mhl|Marshall Islands||Republic of the Marshall Islands
  mk|mkd|North Macedonia||Republic of North Macedonia
  ml|mli|Mali||Republic of Mali
  mm|mmr|Myanmar||Republic of Myanmar
  mn|mng|Mongolia||
  mo|mac|Macao||Macao Special Administrative Region of China
  mp|mnp|Northern Mariana Islands||Commonwealth of the Northern Mariana Islands
  mq|mtq|Martinique||
  mr|mrt|Mauritania||Islamic Republic of Mauritania
  ms|msr|Montserrat||
  mt|mlt|Malta||Republic of Malta
  mu|mus|Mauritius||Republic of Mauritius
  mv|mdv|Maldives||Republic of Maldives
  mw|mwi|Malawi||Republic of Malawi
  mx|mex|Mexico||United Mexican States
  my|mys|Malaysia||
  mz|moz|Mozambique||Republic of Mozambique
  na|nam|Namibia||Republic of Namibia
  nc|ncl|New Caledonia||
  ne|ner|Niger||Republic of the Niger
  nf|nfk|Norfolk Island||
  ng|nga|Nigeria||Federal Republic of Nigeria
  ni|nic|Nicaragua||Republic of Nicaragua
  nl|nld|Netherlands||Kingdom of the Netherlands
  no|nor|Norway||Kingdom of Norway
  np|npl|Nepal||Federal Democratic Republic of Nepal
  nr|nru|Nauru||Republic of Nauru
  nu|niu|Niue||Niue
  nz|nzl|New Zealand||
  om|omn|Oman||Sultanate of Oman
  pa|pan|Panama||Republic of Panama
  pe|per|Peru||Republic of Peru
  pf|pyf|French Polynesia||
  pg|png|Papua New Guinea||Independent State of Papua New Guinea
  ph|phl|Philippines||Republic of the Philippines
  pk|pak|Pakistan||Islamic Republic of Pakistan
  pl|pol|Poland||Republic of Poland
  pm|spm|Saint Pierre and Miquelon||
  pn|pcn|Pitcairn||
  pr|pri|Puerto Rico||
  ps|pse|Palestine, State of||the State of Palestine
  pt|prt|Portugal||Portuguese Republic
  pw|plw|Palau||Republic of Palau
  py|pry|Paraguay||Republic of Paraguay
  qa|qat|Qatar||State of Qatar
  re|reu|Réunion||
  ro|rou|Romania||
  rs|srb|Serbia||Republic of Serbia
  ru|rus|Russian Federation||
  rw|rwa|Rwanda||Rwandese Republic
  sa|sau|Saudi Arabia||Kingdom of Saudi Arabia
  sb|slb|Solomon Islands||
  sc|syc|Seychelles||Republic of Seychelles
  sd|sdn|Sudan||Republic of the Sudan
  se|swe|Sweden||Kingdom of Sweden
  sg|sgp|Singapore||Republic of Singapore
  sh|shn|Saint Helena, Ascension and Tristan da Cunha||
  si|svn|Slovenia||Republic of Slovenia
  sj|sjm|Svalbard and Jan Mayen||
  sk|svk|Slovakia||Slovak Republic
  sl|sle|Sierra Leone||Republic of Sierra Leone
  sm|smr|San Marino||Republic of San Marino
  sn|sen|Senegal||Republic of Senegal
  so|som|Somalia||Federal Republic of Somalia
  sr|sur|Suriname||Republic of Suriname
  ss|ssd|South Sudan||Republic of South Sudan
  st|stp|Sao Tome and Principe||Democratic Republic of Sao Tome and Principe
  sv|slv|El Salvador||Republic of El Salvador
  sx|sxm|Sint Maarten (Dutch part)||Sint Maarten (Dutch part)
  sy|syr|Syrian Arab Republic|Syria|
  sz|swz|Eswatini||Kingdom of Eswatini
  tc|tca|Turks and Caicos Islands||
  td|tcd|Chad||Republic of Chad
  tf|atf|French Southern Territories||
  tg|tgo|Togo||Togolese Republic
  th|tha|Thailand||Kingdom of Thailand
  tj|tjk|Tajikistan||Republic of Tajikistan
  tk|tkl|Tokelau||
  tl|tls|Timor-Leste||Democratic Republic of Timor-Leste
  tm|tkm|Turkmenistan||
  tn|tun|Tunisia||Republic of Tunisia
  to|ton|Tonga||Kingdom of Tonga
  tr|tur|Turkey|Türkiye|Republic of Türkiye
  tt|tto|Trinidad and Tobago||Republic of Trinidad and Tobago
  tv|tuv|Tuvalu||
  tw|twn|Taiwan, Province of China|Taiwan|Taiwan, Province of China
  tz|tza|Tanzania, United Republic of|Tanzania|United Republic of Tanzania
  ua|ukr|Ukraine||
  ug|uga|Uganda||Republic of Uganda
  um|umi|United States Minor Outlying Islands||
  us|usa|United States||United States of America
  uy|ury|Uruguay||Eastern Republic of Uruguay
  uz|uzb|Uzbekistan||Republic of Uzbekistan
  va|vat|Holy See (Vatican City State)||
  vc|vct|Saint Vincent and the Grenadines||
  ve|ven|Venezuela, Bolivarian Republic of|Venezuela|Bolivarian Republic of Venezuela
  vg|vgb|Virgin Islands, British||British Virgin Islands
  vi|vir|Virgin Islands, U.S.||Virgin Islands of the United States
  vn|vnm|Viet Nam|Vietnam|Socialist Republic of Viet Nam
  vu|vut|Vanuatu||Republic of Vanuatu
  wf|wlf|Wallis and Futuna||
  ws|wsm|Samoa||Independent State of Samoa
  ye|yem|Yemen||Republic of Yemen
  yt|myt|Mayotte||
  za|zaf|South Africa||Republic of South Africa
  zm|zmb|Zambia||Republic of Zambia
  zw|zwe|Zimbabwe||Republic of Zimbabwe
  """

  @countries @country_data
             |> String.split("\n", trim: true)
             |> Enum.map(&String.split(&1, "|"))

  @search_terms_by_code Map.new(@countries, fn [code | aliases] ->
                          {code, [code | Enum.reject(aliases, &(&1 == ""))]}
                        end)

  @aliases @countries
           |> Enum.flat_map(fn [code | aliases] ->
             [code | aliases]
             |> Enum.reject(&(&1 == ""))
             |> Enum.map(&{String.downcase(&1), code})
           end)
           |> Map.new()

  @spec code_for(term()) :: binary() | nil
  def code_for(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&Map.get(@aliases, &1))
  end

  def code_for(_value), do: nil

  @spec search_terms_for_code(term()) :: [binary()]
  def search_terms_for_code(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&Map.get(@search_terms_by_code, &1, []))
  end

  def search_terms_for_code(_value), do: []
end
