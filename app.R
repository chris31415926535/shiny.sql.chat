#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

library(shiny)
library(dplyr)
library(dbplyr)
library(DBI)
library(RSQLite)

# boolean to control console messages
debug <- FALSE

# function to connect to a SQLite database, creating a data directory and
# SQLite file if necessary. This could be updated to use a different storage
# mechanism.
db_connect <- function(message_db_schema) {
  # make sure we have a data directory
  if (!dir.exists("data")) dir.create("data")

  # connect to SQLite database, or create one
  con <- DBI::dbConnect(RSQLite::SQLite(), "data/messages.sqlite")

  # if there is no message table, create one using our schema
  if (!"messages" %in% DBI::dbListTables(con)){
    db_clear(con, message_db_schema)
  }

  return(con)
}

db_clear <- function(con, message_db_schema){
  dplyr::copy_to(con, message_db_schema, name = "messages", overwrite = TRUE,  temporary = FALSE )
}

# A separate function in case you want to do any data preparation (e.g. time zone stuff)
read_messages <- function(con){
  dplyr::tbl(con, "messages") %>%
    collect()
}

send_message <- function(con, new_message) {
  RSQLite::dbAppendTable(con, "messages", new_message)
}

# function to render SQL chat messages into HTML that we can style with CSS
# inspired by:
# https://www.r-bloggers.com/2017/07/shiny-chat-in-few-lines-of-code-2/
render_msg_fancy <- function(messages, self_username) {
  div(id = "chat-container",
      class = "chat-container",
      messages %>%
        purrrlyr::by_row(~ div(class =  dplyr::if_else(
          .$username == self_username,
          "chat-message-left", "chat-message-right"),
          a(class = "username", .$username),
          div(class = "message", .$message),
          div(class = "datetime", .$datetime)
        ))
      %>% {.$.out}
  )
}

# Define UI for basic chat application
ui <- fluidPage(
  id = "chatbox-container",

  tags$head(
    tags$script(src = "script.js"),
    tags$link(rel = "stylesheet", type = "text/css", href = "styling.css")
  ),

  # Application title
  titlePanel("Simple SQL-Powered Chat in R Shiny!"),

  uiOutput("messages_fancy"),

  tags$div(textInput("msg_text", label = NULL),
           actionButton("msg_button", "Send", height="30px"),
           style="display:flex"),

  hr(),

  textInput("msg_username", "User Name:", value = "ChatEnthusiast"),
  actionButton("msg_clearchat", "Clear Chat Log")
)


# Server logic for basi cchat
server <- function(input, output) {

  # update username to use random numbers
  shiny::updateTextInput(inputId = "msg_username",
                         value = paste0("ChatEnthusiast", round(runif(n=1, min=1000000,max = 10000000))))

  # convert time to numeric with 2 decimal degrees precision, need to divide by 100 again later
  # Sys.time( ) %>% format("%s%OS2") %>% as.numeric() %>% `/`(100) %>% as.POSIXct(origin = "1970-01-01") %>% format("%s%OS2") %>% as.numeric()
  message_db_schema <- dplyr::tibble(username = character(0),
                                     #datetime = Sys.time()[0], # if you want POSIXct data instead
                                     #datetime = numeric(0),    # if you want to store datetimes as numeric
                                     datetime = character(0),   # we're taking the easy way here
                                     message = character(0))

  con <- db_connect(message_db_schema)

  # set up our messages data locally
  messages_db <- reactiveValues(messages = read_messages(con))

  # look for new messages every n milliseconds
  db_check_timer <- shiny::reactiveTimer(intervalMs = 1000)

  observe({
    db_check_timer()
    if (debug) message("checking table...")
    messages_db$messages <- read_messages(con)

  })

  # button handler for chat clearing
  observeEvent(input$msg_clearchat, {
    if (debug) message("clearing chat log.")

    db_clear(con, message_db_schema)

    messages_db <- reactiveValues(messages = read_messages(con))

  })

  # button handler for sending a message
  observeEvent(input$msg_button, {
    if (debug) message(input$msg_text)

    # only do anything if there's a message
    if (!(input$msg_text == "" | is.null(input$msg_text))) {

      msg_time <- Sys.time( ) %>%
        as.character()

      new_message <- dplyr::tibble(username = input$msg_username,
                                   message = input$msg_text,
                                   datetime = msg_time)

      send_message(con, new_message)

      messages_db$messages <- read_messages(con)

      # clear the message text
      shiny::updateTextInput(inputId = "msg_text",
                             value = "")
    }
  })

  # render the chat data using a custom function
  output$messages_fancy <- shiny::renderUI({
    render_msg_fancy(messages_db$messages, input$msg_username)
  })

}



# Run the application
shinyApp(ui = ui, server = server)
