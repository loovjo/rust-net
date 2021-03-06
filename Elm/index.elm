import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Date
import Time

import Http

import Base

loadingText = "The server is currently loading the results from WCA. This usually takes about one minute."

sortings : List (String, (Base.Competition -> Base.Competition -> Order))
sortings =
    [ ( "Date", (\c1 c2 -> compare (Date.toTime c1.date) (Date.toTime c2.date)) )
    , ( "Name", (\c1 c2 -> compare c1.name c2.name) )
    , ( "Number of people", (\c1 c2 -> compare (List.length c2.competitors) (List.length c1.competitors)) )
    , ( "Number of events", (\c1 c2 -> compare (List.length c2.events) (List.length c1.events)) )
    ]

defaultSort = List.head sortings

main =
    program
        { init = init
        , update = update
        , view = view
        , subscriptions = subs
        }

type alias Model =
    { competitions : List Base.Competition
    , search : String
    , searchPerson : String
    , searchCountry : String
    , sorting : Maybe (String, (Base.Competition -> Base.Competition -> Order))
    , serverLoading : Maybe (Float, Float)
    , lastTime : Maybe Time.Time
    }

init =
    update LoadUpcoming <|
        { competitions = []
        , search = ""
        , searchPerson = ""
        , searchCountry = ""
        , sorting = defaultSort
        , serverLoading = Nothing
        , lastTime = Nothing
        }

type Msg
    = LoadUpcoming
    | LoadProgress
    | ParseUpcoming (Result Http.Error String)
    | ParseProgress (Result Http.Error String)
    | UpdateProgress Time.Time
    | Search String
    | SearchPerson String
    | SearchCountry String
    | SetSorting String

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        SetSorting name ->
            let sorting =
                    List.head <|
                    List.filter (\sort -> Tuple.first sort == name)
                    sortings
            in case sorting of
                Nothing -> model ! []
                Just sorting ->
                    { model | sorting = Just sorting } ! []

        LoadUpcoming ->
            case model.competitions of
                [] ->
                    model !
                    [ Http.send ParseUpcoming
                        <| Http.getString "api/upcoming"
                    ]
                _ -> model ! []

        ParseUpcoming (Ok text) ->
            if text == "e0"
                then model ! []
                else case D.decodeString (D.list Base.decodeComp) text of
                    Ok comps ->
                        { model
                        | competitions = Debug.log "Comps" comps
                        , serverLoading = Nothing
                        } ! []
                    Err err ->
                        let _ = Debug.log "Server error" err
                        in model ! []

        ParseUpcoming (Err err) ->
            let _ = Debug.log "Server error" err
            in model ! []

        ParseProgress (Err err) ->
            let _ = Debug.log "Server error" err
            in model ! []

        ParseProgress (Ok text) ->
            case Debug.log "Result" <| List.map String.toFloat <| String.split " " text of
                [Ok prog, Ok speed] ->
                    let _ = Debug.log "Res" [prog, speed]
                    in { model | serverLoading = Just (prog, speed) } ! []
                _ -> model ! []

        UpdateProgress current ->
            case Debug.log "xyz" <| (model.lastTime, model.serverLoading) of
                (Just lastTime, Just (prog, progSpeed)) ->
                    let diff_s = (current - lastTime) / Time.second
                    in  { model
                        | lastTime = Just current
                        , serverLoading = Just (prog + progSpeed * diff_s, progSpeed * 0.9 ^ (diff_s / 5))
                        } ! []
                _ -> { model | lastTime = Just current } ! []

        LoadProgress ->
            model ! [ Http.send ParseProgress <| Http.getString "prog" ]

        Search st -> { model | search = st } ! []

        SearchPerson st -> { model | searchPerson = st } ! []

        SearchCountry st -> { model | searchCountry = st } ! []

getMatchingComps : Model -> List Base.Competition
getMatchingComps { search, searchPerson, searchCountry, competitions } =
    if search == "" && searchPerson == "" && searchCountry == ""
        then competitions
        else List.filter
            (\comp ->
                (
                    String.contains
                        (String.toLower search)
                        (String.toLower comp.name)
                    && String.contains
                        (String.toLower searchCountry)
                        (String.toLower <| comp.country_name ++ "\0" ++ comp.country_iso ++ "\0" ++ comp.city)
                )
                && List.any
                    (\p ->
                        String.contains
                            (String.toLower searchPerson)
                            (String.toLower p.id)
                        || String.contains
                            (String.toLower searchPerson)
                            (String.toLower p.name)
                    ) comp.competitors
            )
            competitions

view : Model -> Html Msg
view model =
    div []
     <| pageTitle model
     :: [ genSearch model
        , case model.sorting of
            Just sorting -> renderComps <| List.sortWith (Tuple.second sorting) <| getMatchingComps model
            Nothing -> renderComps <| getMatchingComps model
        , wcaDisc
        , if model.competitions == []
             then div [ id "loadingcircle" ] []
             else div [] []
        , case model.serverLoading of
            Just (prog, _) ->
                div [ id "loader" ]
                    [ p [ id "loadingtext" ] [ text loadingText ]

                    , div [ id "loadingbar_out" ]
                        [ div [ id "loading_in", style [("width", (toString <| 100 * prog) ++ "%")] ] []
                        ]
                    ]
            Nothing -> div [] []
        -- , a [href "rest.html"] [ text "Other things (links to random games etc.)" ]
        ]

pageTitle : Model -> Html Msg
pageTitle model =
    div []
        [ h1 [ style
            [ ("text-align", "center")
            , ("padding-top", "30px")
            , ("padding-bottom", "30px")
            ] ] [ text "Cubechance" ]
        , hr [] []
        ]

genSearch model =
    table [ id "search" ]
        [ tr []
            [ th []
                [ text "Search competition: "
                , input [ placeholder "Competition", value model.search, onInput Search ] []
                ]
            , th []
                [ text "Search person: "
                , input [ placeholder "WCA ID / Name", value model.searchPerson, onInput SearchPerson ] []
                ]
            , th []
                [ text "Search country/city: "
                , input [ placeholder "London, China, ect.", value model.searchCountry, onInput SearchCountry ] []
                ]
            , th []
                [ text "Sort by: "
                , viewDropdown model
                ]
            ]
        ]

viewDropdown : Model -> Html Msg
viewDropdown model =
    select [ onInput SetSorting ] <|
        List.map
            (\(name, _) ->
                option [ selected <| Just name == Maybe.map Tuple.first model.sorting ]
                    [ text name ]
            )
        sortings


renderComps : List Base.Competition -> Html Msg
renderComps comps =
    table [ id "list" ] <|
    tr []
        [ th [] [ text "Competition" ]
        , th [] [ text "Country" ]
        , th [] [ text "Date" ]
        ]
     :: List.map (\comp ->
            tr []
            [ a [href <| "/comp.html?" ++ comp.id] [ td [] [text comp.name] ]
            , td []
                [ span [ class <| "flag-icon flag-icon-" ++ String.toLower comp.country_iso ] []
                , text " - "
                , b [] [ text <| comp.country_name]
                , text <| ", " ++ comp.city
                ]
            , td [] [text <| Base.viewDate comp.date]
            ]
        ) comps

wcaDisc =
    p [style [( "font-size", "9pt" )]]
        [ text "Data taken from World Cube Association ("
        , a [ href "https://www.worldcubeassociation.org" ] [ text "https://www.worldcubeassociation.org" ]
        , text ") daily. This is not the actual information, it can be found "
        , a [ href "https://www.worldcubeassociation.org/results" ] [ text "here" ]
        , text ". "
        ]


subs model =
    Sub.batch
    [ Time.every (Time.second * 2) <| always LoadUpcoming
    , Time.every (Time.second / 2) <| always LoadProgress
    , Time.every (Time.second / 10) <| UpdateProgress
    ]
