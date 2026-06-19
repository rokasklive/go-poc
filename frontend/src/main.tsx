import React from 'react'
import ReactDOM from 'react-dom/client'
import '@radix-ui/themes/styles.css'
import { Theme } from '@radix-ui/themes'
import App from './App'
import './styles.css'

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <Theme appearance="dark" accentColor="indigo" grayColor="slate" radius="medium">
      <App />
    </Theme>
  </React.StrictMode>,
)
