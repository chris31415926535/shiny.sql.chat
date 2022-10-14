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
library(DBI)
library(RSQLite)

# boolean to control console messages
debug <- FALSE

# Define UI for basic chat application
ui <- fluidPage(

  tags$head(
    tags$script(src = "script.js"),
    tags$link(rel = "stylesheet", type = "text/css", href = "chat_styling.css")
  ),



  # javascript from https://github.com/Appsilon/shiny.collections/blob/master/inst/examples/www/script.js
#   tags$script(HTML("
#   jQuery(document).ready(function(){
#   jQuery('#msg_text').keypress(function(evt){
#     if (evt.keyCode == 13){
#       // Enter, simulate clicking send
#       jQuery('#msg_button').click();
#     }
#   });
# })
#
# // this autoscroll doesn't work though
# // Scrolling down
# var oldContent = null;
# window.setInterval(function() {
#   var elem = document.getElementById('chat-container');
#   if (oldContent != elem.innerHTML){
#     scrollToBottom();
#   }
#   oldContent = elem.innerHTML;
# }, 300);
#
# function scrollToBottom(){
#   var elem = document.getElementById('chat-container');
#   elem.scrollTop = elem.scrollHeight;
# }
#                    ")),

  # Application title
  titlePanel("Simple SQL-Powered Chat in R Shiny!"),

  # Sidebar with a slider input for number of bins
  sidebarLayout(
    sidebarPanel(width = 3,
      textInput("msg_username",
                "User Name:",
                value = "Chat Enthusiast"),
      textInput("msg_text",
                "Message Text:"),
      actionButton("msg_button",
                   "Send Message"),
      hr(),
      actionButton("msg_clearchat",
                   "Clear Chat Log"),
    ),

    # Show a plot of the generated distribution
    mainPanel(
      column(width = 6, uiOutput("messages_fancy"))
    )
  )
)


# inspired by:
# https://www.r-bloggers.com/2017/07/shiny-chat-in-few-lines-of-code-2/
render_msg_divs_list <- function(messages) {
  div(class = "ui very relaxed list",
      messages %>%
        #arrange(time) %>%
        purrrlyr::by_row(~ div(class = "item",
                               a(class = "header", .$username),
                               div(class = "description", .$message)
        )) %>% {.$.out}
)
}

render_msg_fancy <- function(messages, self_username) {
  div(class = "ui chat-container",
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

server <- function(input, output) {

  # update username to use random numbers
  shiny::updateTextInput(inputId = "msg_username",
                         value = paste0("Chat Enthusiast", round(runif(n=1, min=1000000,max = 10000000))))

  # convert time to numeric with 2 decimal degrees precision, need to divide by 100 again later
  # Sys.time( ) %>% format("%s%OS2") %>% as.numeric() %>% `/`(100) %>% as.POSIXct(origin = "1970-01-01") %>% format("%s%OS2") %>% as.numeric()
  message_db_schema <- dplyr::tibble(username = character(0),
                                     #datetime = Sys.time()[0], # if you want POSIXct data instead
                                     #datetime = numeric(0),    # if you want to store datetimes as numeric
                                     datetime = character(0),   # we're taking the easy way here
                                     message = character(0))

  con <- DBI::dbConnect(RSQLite::SQLite(), "data/messages.sqlite")

  if (!"messages" %in% DBI::dbListTables(con)){
    dplyr::copy_to(con, message_db_schema, name = "messages", overwrite = TRUE,  temporary = FALSE )
  }

  messages_db <- reactiveValues(messages = read_messages(con))

  db_check_timer <- shiny::reactiveTimer(intervalMs = 1000)

  # check the table for updates each second
  observe({
    db_check_timer()
    if (debug) message("checking table...")
    messages_db$messages <- read_messages(con)

  })

  observeEvent(input$msg_clearchat, {
    message("clearing chat log.")
    dplyr::copy_to(con, message_db_schema, name = "messages", overwrite = TRUE,  temporary = FALSE )
    messages_db <- reactiveValues(messages = read_messages(con))

  })

  observeEvent(input$msg_button, {
    message(input$msg_text)

    msg_time <- Sys.time( ) %>%
      as.character()

    new_message <- dplyr::tibble(username = input$msg_username,
                                 message = input$msg_text,
                                 datetime = msg_time)

    RSQLite::dbAppendTable(con, "messages", new_message)

    messages_db$messages <- read_messages(con)

    # clear the message text
    shiny::updateTextInput(inputId = "msg_text",
                           value = "")
  })



  output$messages_table <- shiny::renderTable(messages_db$messages)

  output$messages_list <- shiny::renderUI({
    render_msg_divs(messages_db$messages)
  })

  output$messages_fancy <- shiny::renderUI({
    render_msg_fancy(messages_db$messages, input$msg_username)
  })

}


# A separate function in case you want to do any data preparation (e.g. time zone stuff)
read_messages <- function(con){
  dplyr::tbl(con, "messages") %>%
    collect()
}




# Run the application
shinyApp(ui = ui, server = server)
