# Load required packages
library(shiny)
library(shinyjs)
library(DBI)
library(dplyr)
library(dbplyr)
library(RSQLite)
library(tidyr)
library(glue)
library(DT)
library(shinyWidgets)

appCSS <- "
#loading-content {
  position: absolute;
  background: #D3D3D3;
  opacity: 0.9;
  z-index: 100;
  left: 0;
  right: 0;
  height: 100%;
  text-align: center;
  color: #000000;
}
"
# database location
db_location <- "db/ccle.db"

# Define UI for application
ui <- fluidPage(useShinyjs(),
                inlineCSS(appCSS),
                
                # Loading message
                div(id = "loading-content", h2("Loading Dataset...")),
                hidden(div(
                  id = "app-content",
                  # Application title
                  titlePanel("Somatic Mutations in Cancer Cell Lines"),
                  p(
                    "This tool output a table with cancer cell lines that contain specific mutations in any gene of interest. The dataset, which contain all mutations present in all sequenced models,
 is downloaded from ``cellmodelpassports``."),

                  tagList(
                    p(strong("Steps:")),
                    tags$ul(
                      tags$li("Choose a Gene."),
                      tags$li("Choose Columns to Show."),
                      tags$li("Click on `View Data` to show the table."),
                      tags$li("Click `Download Data Table` to download the data.")
                    )
                  ),
                  # Sidebar layout with input and output definitions
                  sidebarLayout(
                    sidebarPanel(
                      selectizeInput(
                        'gene',
                        "Select Gene:",
                        choices = NULL,
                        options = list(searchable = TRUE),
                        selected = NULL,
                        multiple = FALSE
                      ),
                      uiOutput("picker"),
                      actionButton("view", "View Data"),
                      tags$br(),
                      tags$br(),
                      downloadLink('downloadData', 'Download Data Table'),
                    ),
                    
                    # Main panel to display information
                    mainPanel(# Output: Display information about the cell line
                      
                      DT::dataTableOutput("dataTable"), tags$br(), )
                  )
                )))

# Define server logic required
server <- function(input, output, session) {
  get_unique_genes <- function() {
    con <- dbConnect(SQLite(), db_location)
    ret <-  tbl(con, "view_unique_genes") %>% pull(Gene)
    dbDisconnect(con)
    ret
  }
  
  cell_models <- reactive({
    con <- dbConnect(SQLite(), db_location)
    mutations <- tbl(con, "SomaticMutations")
    ret <- dplyr::filter(mutations, gene_symbol %in% local(input$gene)) %>%
      as_tibble()
    dbDisconnect(con)
    ret
  })
  
  get_data <- function(models) {
    con <- dbConnect(SQLite(), db_location)
    model <- tbl(con, "view_unique_cellLines")
    selected_profiles <- unique(pull(models, model_name)) 
    ret <- dplyr::filter(model, model_name %in% selected_profiles) %>%
      as_tibble() %>%
      left_join(models, relationship = "many-to-many") %>%
      arrange(model_name)  %>%
      distinct()  # This removes duplicate rows
    dbDisconnect(con)
    ret
  }
  
  updateSelectizeInput(
    session,
    "gene",
    choices = get_unique_genes(),
    server = TRUE,
    selected = "",
  )
  
  final_data <- reactive({
    models <- cell_models()
    get_data(models)
  })
  

  
  output$picker <- renderUI({
    pickerInput(
      inputId = 'pick',
      label = 'Select Columns:',
      choices = colnames(final_data()),
      options = list(`actions-box` = TRUE, `selected-text-format` = "count > 2", `count-selected-text` = "{0}/{1} columns (selected)"),
      multiple = TRUE,
      selected = c("model_id", "gene_symbol", "ensembl_gene_id", "model_name", "cdna_mutation", "protein_mutation","type", "effect", "vaf", "data_type")
    )
  })
  
  datasetInput <- eventReactive(input$view, {
    datasetInput <- final_data() %>%
      select(input$pick)
    
    return(datasetInput)
    
  })
  
  output$dataTable = DT::renderDataTable({
    datasetInput()
  })
  observe({
    validate(need(input$gene, "gene"), )
  })
  output$downloadData <- downloadHandler(
    filename = function() {
      req(input$gene)  # Ensure input$gene is available
      paste0("ccle_mutations_", input$gene, ".csv")  # Use input$gene in filename
    },
    content = function(con) {
      readr::write_csv(datasetInput(), con)
    }
  )
  # Simulate work being done for 1 second
  Sys.sleep(0.5)
  
  # Hide the loading message when the rest of the server function has executed
  shinyjs::hide(id = "loading-content",
                anim = TRUE,
                animType = "fade")
  shinyjs::show("app-content")
}

# Run the application
shinyApp(ui = ui, server = server)