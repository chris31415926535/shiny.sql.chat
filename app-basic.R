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

# Define UI for basic chat application
ui <- fluidPage(

  # Application title
  titlePanel("Simple SQL-Powered Chat in R Shiny!"),

  # Sidebar with user input and chat controls
  sidebarLayout(
    sidebarPanel(width = 3,
                 textInput("msg_text", "Message Text:"),
                 actionButton("msg_button", "Send Message"),
                 hr(),
                 actionButton("msg_clearchat", "Clear Chat Log")),

    # main chat panel
    mainPanel(tableOutput("messages_basic")))
)

# A separate function in case you want to do any data preparation (e.g. time zone stuff)
read_messages <- function(con){
  dplyr::tbl(con, "messages") %>%
    collect()
}

server <- function(input, output) {

  # assign username with random numbers
  msg_username <- paste0("ChatEnthusiast", round(runif(n=1, min=10^6,max = 10^7)))


  # Set up message schema
  message_db_schema <- dplyr::tibble(username = character(0),
                                     datetime = character(0),
                                     message = character(0))

  # connect to database
  con <- DBI::dbConnect(RSQLite::SQLite(), "data/messages.sqlite")

  # if there is no table named "messages," create one using our schema
  if (!"messages" %in% DBI::dbListTables(con)){
    dplyr::copy_to(con, message_db_schema, name = "messages", overwrite = TRUE,  temporary = FALSE )
  }

  # read initial set of messages
  messages_db <- reactiveValues(messages = read_messages(con))


  # create a reactive timer to check the database regularly
  db_check_timer <- shiny::reactiveTimer(intervalMs = 1000)

  # check the table for updates each second
  observe({
    db_check_timer()
    messages_db$messages <- read_messages(con)
  })

  # Button handler for clearing the chat
  observeEvent(input$msg_clearchat, {
    dplyr::copy_to(con, message_db_schema, name = "messages", overwrite = TRUE,  temporary = FALSE )
    messages_db <- reactiveValues(messages = read_messages(con))
  })

  # Button handler for sending a message
  observeEvent(input$msg_button, {

        # only do anything if there's a message
    if (!(input$msg_text == "" | is.null(input$msg_text))) {

      msg_time <- Sys.time() %>%
        as.character()

      new_message <- dplyr::tibble(username = msg_username,
                                   message = input$msg_text,
                                   datetime = msg_time)

      RSQLite::dbAppendTable(con, "messages", new_message)

      messages_db$messages <- read_messages(con)

      # clear the message text
      shiny::updateTextInput(inputId = "msg_text",
                             value = "")
    }
  })

  # Display our messages using a basic table output
  output$messages_basic <- shiny::renderTable(messages_db$messages)

}


# Run the application
shinyApp(ui = ui, server = server)
